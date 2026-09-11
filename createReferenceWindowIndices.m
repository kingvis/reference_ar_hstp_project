%% createReferenceWindowIndices.m
% Create leakage-safe window manifests for the reference AR + Hs/Tp study.
%
% This script deliberately DOES NOT copy raw signal values into thousands of
% window CSV files. It records the source run and row bounds of every window.
% The later AR-feature script reads each segment directly from its 5-Hz source
% file. This avoids duplicated storage and makes source-run provenance clear.
%
% Candidate durations are 30, 60, and 120 seconds. The final duration will
% be selected using validation RUN-level performance only. Test runs are not
% used to choose the duration or tune the CNN.
 
clearvars
clc
 
thisFolder = fileparts(mfilename('fullpath'));
cd(thisFolder);
 
preparedDir = fullfile(thisFolder, 'dataset_reference_ideal_5hz');
sourceIndexPath = fullfile(preparedDir, 'source_run_index.csv');
windowIndexDir = fullfile(preparedDir, 'window_indices');
 
fs_Hz = 5;
windowDurations_s = [30, 60, 120];
overlapFraction = 0.50;
 
if ~isfolder(preparedDir) || ~isfile(sourceIndexPath)
    error('createReferenceWindowIndices:missingPreparedDataset', ...
        ['Prepared 5-Hz data were not found. Run ', ...
         'prepareReferenceARDataset.m first.']);
end
 
sourceRunIndex = readtable(sourceIndexPath);
localRequireVariables(sourceRunIndex, ...
    {'runID','Hs','Tp','phaseSeed','split','faultName','severity', ...
     'processedFile','nPreparedSamples','preparedFs_Hz'});
 
if height(sourceRunIndex) ~= 500
    error('createReferenceWindowIndices:wrongRunCount', ...
        'Expected 500 source runs, found %d.', height(sourceRunIndex));
end
 
sourceRunIndex.split = string(sourceRunIndex.split);
sourceRunIndex.faultName = string(sourceRunIndex.faultName);
sourceRunIndex.processedFile = string(sourceRunIndex.processedFile);
 
if any(sourceRunIndex.nPreparedSamples ~= 9501) || ...
        any(abs(sourceRunIndex.preparedFs_Hz - fs_Hz) > eps)
    error('createReferenceWindowIndices:unexpectedPreparedData', ...
        'Every prepared run must contain 9,501 samples at 5 Hz.');
end
 
if sum(sourceRunIndex.split == "train") ~= 300 || ...
        sum(sourceRunIndex.split == "validation") ~= 100 || ...
        sum(sourceRunIndex.split == "test") ~= 100
    error('createReferenceWindowIndices:invalidSplit', ...
        'Expected the fixed 300/100/100 source-run split.');
end
 
if ~isfolder(windowIndexDir)
    mkdir(windowIndexDir);
end
 
nCandidates = numel(windowDurations_s);
summaryDuration_s = zeros(nCandidates, 1);
summaryLength_pts = zeros(nCandidates, 1);
summaryStep_pts = zeros(nCandidates, 1);
summaryTotalWindows = zeros(nCandidates, 1);
summaryTrainWindows = zeros(nCandidates, 1);
summaryValidationWindows = zeros(nCandidates, 1);
summaryTestWindows = zeros(nCandidates, 1);
summaryIndexFile = strings(nCandidates, 1);
 
fprintf('\nCreating source-run-safe window indices\n');
fprintf('Candidate durations: %s seconds | overlap: %.0f%%\n\n', ...
    mat2str(windowDurations_s), 100 * overlapFraction);
 
for candidate = 1:nCandidates
 
    windowDuration_s = windowDurations_s(candidate);
    windowLength_pts = round(windowDuration_s * fs_Hz);
    step_pts = round(windowLength_pts * (1 - overlapFraction));
 
    if windowLength_pts < 2 || step_pts < 1
        error('createReferenceWindowIndices:invalidWindowSettings', ...
            'Window duration and overlap produce invalid sample bounds.');
    end
 
    nWindowsForRun = floor( ...
        (sourceRunIndex.nPreparedSamples - windowLength_pts) ./ step_pts) + 1;
 
    if any(nWindowsForRun < 1)
        error('createReferenceWindowIndices:windowLongerThanRun', ...
            'A %g-s window is longer than at least one prepared run.', ...
            windowDuration_s);
    end
 
    nWindows = sum(nWindowsForRun);
 
    windowID = (1:nWindows)';
    sourceRunID = zeros(nWindows, 1);
    processedFile = strings(nWindows, 1);
    split = strings(nWindows, 1);
    phaseSeed = zeros(nWindows, 1);
    Hs = zeros(nWindows, 1);
    Tp = zeros(nWindows, 1);
    faultName = strings(nWindows, 1);
    severity = zeros(nWindows, 1);
    startRow = zeros(nWindows, 1);
    endRow = zeros(nWindows, 1);
    startTime_s = zeros(nWindows, 1);
    endTime_s = zeros(nWindows, 1);
 
    nextRow = 0;
    for sourceRow = 1:height(sourceRunIndex)
        thisCount = nWindowsForRun(sourceRow);
        startRows = 1 + (0:thisCount-1)' * step_pts;
        endRows = startRows + windowLength_pts - 1;
        rows = nextRow + (1:thisCount);
 
        sourceRunID(rows) = sourceRunIndex.runID(sourceRow);
        processedFile(rows) = repmat( ...
            sourceRunIndex.processedFile(sourceRow), thisCount, 1);
        split(rows) = repmat(sourceRunIndex.split(sourceRow), thisCount, 1);
        phaseSeed(rows) = sourceRunIndex.phaseSeed(sourceRow);
        Hs(rows) = sourceRunIndex.Hs(sourceRow);
        Tp(rows) = sourceRunIndex.Tp(sourceRow);
        faultName(rows) = repmat( ...
            sourceRunIndex.faultName(sourceRow), thisCount, 1);
        severity(rows) = sourceRunIndex.severity(sourceRow);
        startRow(rows) = startRows;
        endRow(rows) = endRows;
 
        % Prepared source files start at exactly 100 s after ramp removal.
        startTime_s(rows) = 100 + (startRows - 1) / fs_Hz;
        endTime_s(rows) = 100 + (endRows - 1) / fs_Hz;
 
        nextRow = nextRow + thisCount;
    end
 
    windowIndex = table( ...
        windowID, sourceRunID, processedFile, split, phaseSeed, Hs, Tp, ...
        faultName, severity, startRow, endRow, startTime_s, endTime_s, ...
        'VariableNames', {'windowID','sourceRunID','processedFile','split', ...
        'phaseSeed','Hs','Tp','faultName','severity','startRow','endRow', ...
        'startTime_s','endTime_s'});
 
    localValidateWindowIndex(windowIndex, sourceRunIndex, windowLength_pts);
 
    indexFile = sprintf('window_index_%03ds.csv', windowDuration_s);
    indexPath = fullfile(windowIndexDir, indexFile);
    writetable(windowIndex, indexPath);
 
    summaryDuration_s(candidate) = windowDuration_s;
    summaryLength_pts(candidate) = windowLength_pts;
    summaryStep_pts(candidate) = step_pts;
    summaryTotalWindows(candidate) = height(windowIndex);
    summaryTrainWindows(candidate) = sum(windowIndex.split == "train");
    summaryValidationWindows(candidate) = sum(windowIndex.split == "validation");
    summaryTestWindows(candidate) = sum(windowIndex.split == "test");
    summaryIndexFile(candidate) = string(indexFile);
 
    fprintf(['%3d-s windows: %d total | %d train | %d validation | ', ...
             '%d test | index %s\n'], ...
        windowDuration_s, height(windowIndex), ...
        summaryTrainWindows(candidate), summaryValidationWindows(candidate), ...
        summaryTestWindows(candidate), indexFile);
end
 
windowDesignSummary = table( ...
    summaryDuration_s, summaryLength_pts, summaryStep_pts, ...
    summaryTotalWindows, summaryTrainWindows, summaryValidationWindows, ...
    summaryTestWindows, summaryIndexFile, ...
    'VariableNames', {'windowDuration_s','windowLength_pts','step_pts', ...
    'totalWindows','trainWindows','validationWindows','testWindows', ...
    'indexFile'});
 
summaryPath = fullfile(windowIndexDir, 'window_design_summary.csv');
writetable(windowDesignSummary, summaryPath);
 
fprintf('\n====================================================\n');
fprintf('Window-index creation complete.\n');
fprintf('No signal values were duplicated and no AR model was fitted.\n');
fprintf('Summary: %s\n', summaryPath);
fprintf('====================================================\n');
 
function localRequireVariables(T, requiredNames)
    missing = requiredNames(~ismember(requiredNames, T.Properties.VariableNames));
    if ~isempty(missing)
        error('createReferenceWindowIndices:missingVariable', ...
            'Required table variable(s) missing: %s', strjoin(missing, ', '));
    end
end
 
function localValidateWindowIndex(windowIndex, sourceRunIndex, windowLength_pts)
    if any(windowIndex.startRow < 1) || ...
            any(windowIndex.endRow < windowIndex.startRow) || ...
            any(windowIndex.endRow - windowIndex.startRow + 1 ~= windowLength_pts)
        error('createReferenceWindowIndices:invalidBounds', ...
            'Window row bounds are invalid.');
    end
 
    for sourceRow = 1:height(sourceRunIndex)
        sourceID = sourceRunIndex.runID(sourceRow);
        rows = windowIndex.sourceRunID == sourceID;
 
        if any(windowIndex.endRow(rows) > sourceRunIndex.nPreparedSamples(sourceRow))
            error('createReferenceWindowIndices:boundsExceedSource', ...
                'A window exceeds source run %d.', sourceID);
        end
 
        if any(windowIndex.split(rows) ~= sourceRunIndex.split(sourceRow))
            error('createReferenceWindowIndices:splitLeakage', ...
                'A window has a split different from its source run %d.', sourceID);
        end
    end
end