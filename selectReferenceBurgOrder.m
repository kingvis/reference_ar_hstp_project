%% selectReferenceBurgOrder.m
% Select a common Burg AR order for each candidate window duration using
% HEALTHY TRAINING RUNS ONLY. Validation and test runs are never read here.
%
% A common order is needed because a 1-D CNN requires every sample to have
% the same AR-tensor height. For each demeaned signal window and order p,
% this script computes
%
%   AICc(p) = N * log(sigma_p^2) + 2p + 2p(p+1)/(N-p-1)
%
% where sigma_p^2 is the Burg innovation variance. AIC differences are
% measured relative to AR(1) inside each signal/window before aggregation,
% avoiding domination by the force channel's larger physical units. The
% selected common order is the LOWEST order within two median delta-AICc
% units of the minimum across all selected healthy training windows and all
% six measured channels. AICc is used because the shortest candidate window
% has only 150 samples, where ordinary AIC can favour excessive order.
 
clearvars
clc
 
thisFolder = fileparts(mfilename('fullpath'));
cd(thisFolder);
 
preparedDir = fullfile(thisFolder, 'dataset_reference_ideal_5hz');
windowIndexDir = fullfile(preparedDir, 'window_indices');
outputDir = fullfile(preparedDir, 'ar_order_selection');
 
fs_Hz = 5;
candidateDurations_s = [30, 60, 120];
candidateOrders = 1:30;
maxProbeWindowsPerHealthyRun = 10;
signalNames = {'surge_m','heave_m','pitch_rad', ...
    'relDisp_m','relVel_mps','ptoForce_N'};
 
if exist('arburg', 'file') ~= 2
    error('selectReferenceBurgOrder:missingArburg', ...
        ['Burg AR estimation requires arburg(). Install/enable ', ...
         'Signal Processing Toolbox.']);
end
 
if ~isfolder(preparedDir) || ~isfolder(windowIndexDir)
    error('selectReferenceBurgOrder:missingWindowIndices', ...
        'Run createReferenceWindowIndices.m first.');
end
 
if ~isfolder(outputDir)
    mkdir(outputDir);
end
 
nCandidates = numel(candidateDurations_s);
durationOut = zeros(nCandidates, 1);
windowLengthOut = zeros(nCandidates, 1);
healthyTrainRunCountOut = zeros(nCandidates, 1);
probeWindowCountOut = zeros(nCandidates, 1);
probeFitsOut = zeros(nCandidates, 1);
selectedOrderOut = zeros(nCandidates, 1);
selectionMethodOut = strings(nCandidates, 1);
aicFileOut = strings(nCandidates, 1);
 
fprintf('\nSelecting Burg AR orders from healthy training windows only\n');
fprintf('Candidate orders: %s | maximum probes per healthy source run: %d\n\n', ...
    mat2str(candidateOrders), maxProbeWindowsPerHealthyRun);
 
for durationIndex = 1:nCandidates
 
    duration_s = candidateDurations_s(durationIndex);
    indexPath = fullfile(windowIndexDir, ...
        sprintf('window_index_%03ds.csv', duration_s));
 
    if ~isfile(indexPath)
        error('selectReferenceBurgOrder:missingIndexFile', ...
            'Cannot find %s.', indexPath);
    end
 
    windowIndex = readtable(indexPath);
    localRequireVariables(windowIndex, ...
        {'sourceRunID','processedFile','split','severity','startRow','endRow'});
    windowIndex.split = string(windowIndex.split);
    windowIndex.processedFile = string(windowIndex.processedFile);
 
    healthyTrainingRows = ...
        windowIndex.split == "train" & abs(windowIndex.severity - 1.0) < eps;
    healthyTraining = windowIndex(healthyTrainingRows, :);
 
    healthyRunIDs = unique(healthyTraining.sourceRunID);
    if numel(healthyRunIDs) ~= 60
        error('selectReferenceBurgOrder:wrongHealthyTrainingRuns', ...
            'Expected 60 healthy training source runs, found %d.', ...
            numel(healthyRunIDs));
    end
 
    probeRows = localChooseEvenlySpacedProbeRows( ...
        healthyTraining, healthyRunIDs, maxProbeWindowsPerHealthyRun);
    probes = healthyTraining(probeRows, :);
 
    nProbeWindows = height(probes);
    nSignals = numel(signalNames);
    nOrders = numel(candidateOrders);
 
    deltaAICc = zeros(nProbeWindows, nOrders, nSignals);
    localBestOrder = zeros(nProbeWindows, nSignals);
    loadedPreparedPath = "";
 
    for probeIndex = 1:nProbeWindows
 
        preparedPath = string(fullfile( ...
            preparedDir, probes.processedFile(probeIndex)));
        if preparedPath ~= loadedPreparedPath
            if ~isfile(preparedPath)
                error('selectReferenceBurgOrder:missingPreparedFile', ...
                    'Prepared source file is missing: %s', preparedPath);
            end
 
            source = readtable(preparedPath);
            localRequireVariables(source, [{'time_s'}, signalNames]);
            loadedPreparedPath = preparedPath;
        end
 
        startRow = probes.startRow(probeIndex);
        endRow = probes.endRow(probeIndex);
        if startRow < 1 || endRow > height(source) || endRow < startRow
            error('selectReferenceBurgOrder:invalidWindowBounds', ...
                'Invalid bounds for source run %d.', probes.sourceRunID(probeIndex));
        end
 
        for signalIndex = 1:nSignals
            x = source.(signalNames{signalIndex})(startRow:endRow);
            x = x - mean(x);
 
            if any(~isfinite(x)) || sum(x.^2) <= eps
                error('selectReferenceBurgOrder:invalidSignal', ...
                    ['Healthy source run %d has a non-finite or zero-energy ', ...
                     'window in %s.'], ...
                    probes.sourceRunID(probeIndex), signalNames{signalIndex});
            end
 
            aicc = zeros(1, nOrders);
            for orderIndex = 1:nOrders
                p = candidateOrders(orderIndex);
                [~, innovationVariance] = arburg(x, p);
                nSamples = numel(x);
                aic = nSamples * log(max(real(innovationVariance), realmin)) + 2 * p;
                aicc(orderIndex) = aic + ...
                    (2 * p * (p + 1)) / (nSamples - p - 1);
            end
 
            deltaAICc(probeIndex, :, signalIndex) = aicc - aicc(1);
            [~, bestIndex] = min(aicc);
            localBestOrder(probeIndex, signalIndex) = candidateOrders(bestIndex);
        end
    end
 
    medianDeltaAICc = zeros(nOrders, 1);
    fractionLocalBest = zeros(nOrders, 1);
    for orderIndex = 1:nOrders
        values = deltaAICc(:, orderIndex, :);
        medianDeltaAICc(orderIndex) = median(values(:));
        fractionLocalBest(orderIndex) = mean(localBestOrder(:) == ...
            candidateOrders(orderIndex));
    end
 
    minimumMedianDeltaAICc = min(medianDeltaAICc);
    eligibleOrders = find(medianDeltaAICc <= minimumMedianDeltaAICc + 2);
    selectedIndex = eligibleOrders(1);
    selectedOrder = candidateOrders(selectedIndex);
 
    % Signal-specific summaries expose whether one channel disagrees with
    % the common order. They are diagnostics, not extra model inputs.
    signalNameOut = strings(nSignals * nOrders, 1);
    orderOut = zeros(nSignals * nOrders, 1);
    medianDeltaAICcBySignal = zeros(nSignals * nOrders, 1);
    fractionLocalBestBySignal = zeros(nSignals * nOrders, 1);
    row = 0;
    for signalIndex = 1:nSignals
        for orderIndex = 1:nOrders
            row = row + 1;
            signalNameOut(row) = string(signalNames{signalIndex});
            orderOut(row) = candidateOrders(orderIndex);
            medianDeltaAICcBySignal(row) = median( ...
                deltaAICc(:, orderIndex, signalIndex));
            fractionLocalBestBySignal(row) = mean( ...
                localBestOrder(:, signalIndex) == candidateOrders(orderIndex));
        end
    end
 
    globalSummary = table( ...
        repmat(duration_s, nOrders, 1), candidateOrders', medianDeltaAICc, ...
        fractionLocalBest, candidateOrders' == selectedOrder, ...
        'VariableNames', {'windowDuration_s','arOrder', ...
        'medianDeltaAICc_relativeToAR1','fractionOfProbeFitsLocallyBest', ...
        'selectedCommonOrder'});
 
    signalSummary = table( ...
        repmat(duration_s, nSignals * nOrders, 1), signalNameOut, orderOut, ...
        medianDeltaAICcBySignal, fractionLocalBestBySignal, ...
        'VariableNames', {'windowDuration_s','signalName','arOrder', ...
        'medianDeltaAICc_relativeToAR1','fractionOfProbeFitsLocallyBest'});
 
    aicFile = sprintf('burg_aicc_summary_%03ds.csv', duration_s);
    writetable(globalSummary, fullfile(outputDir, aicFile));
    writetable(signalSummary, fullfile(outputDir, ...
        sprintf('burg_aicc_by_signal_%03ds.csv', duration_s)));
 
    durationOut(durationIndex) = duration_s;
    windowLengthOut(durationIndex) = probes.endRow(1) - probes.startRow(1) + 1;
    healthyTrainRunCountOut(durationIndex) = numel(healthyRunIDs);
    probeWindowCountOut(durationIndex) = nProbeWindows;
    probeFitsOut(durationIndex) = nProbeWindows * nSignals;
    selectedOrderOut(durationIndex) = selectedOrder;
    selectionMethodOut(durationIndex) = ...
        "lowest order within 2 median delta-AICc units of the minimum";
    aicFileOut(durationIndex) = string(aicFile);
 
    fprintf(['%3d-s windows | healthy train runs: %d | probe windows: %d | ', ...
             'probe fits: %d | selected Burg AR(%d)\n'], ...
        duration_s, numel(healthyRunIDs), nProbeWindows, ...
        nProbeWindows * nSignals, selectedOrder);
end
 
selectionSummary = table( ...
    durationOut, windowLengthOut, healthyTrainRunCountOut, probeWindowCountOut, ...
    probeFitsOut, selectedOrderOut, selectionMethodOut, aicFileOut, ...
    'VariableNames', {'windowDuration_s','windowLength_pts', ...
    'healthyTrainingSourceRuns','probeWindows','probeSignalFits', ...
    'selectedBurgOrder','selectionMethod','globalAICcSummaryFile'});
 
summaryPath = fullfile(outputDir, 'burg_order_selection_summary.csv');
writetable(selectionSummary, summaryPath);
 
fprintf('\n====================================================\n');
fprintf('Burg-order selection complete.\n');
fprintf('Results: %s\n', summaryPath);
fprintf('Validation and test source runs were not used.\n');
fprintf('====================================================\n');
 
function localRequireVariables(T, requiredNames)
    missing = requiredNames(~ismember(requiredNames, T.Properties.VariableNames));
    if ~isempty(missing)
        error('selectReferenceBurgOrder:missingVariable', ...
            'Required table variable(s) missing: %s', strjoin(missing, ', '));
    end
end
 
function selectedRows = localChooseEvenlySpacedProbeRows( ...
        healthyTraining, healthyRunIDs, maxPerRun)
    selectedRows = [];
 
    for runIndex = 1:numel(healthyRunIDs)
        rowsForRun = find( ...
            healthyTraining.sourceRunID == healthyRunIDs(runIndex));
        nSelect = min(maxPerRun, numel(rowsForRun));
        positions = unique(round(linspace(1, numel(rowsForRun), nSelect)));
        selectedRows = [selectedRows; rowsForRun(positions)]; %#ok<AGROW>
    end
end