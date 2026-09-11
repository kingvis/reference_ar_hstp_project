%% prepareReferenceARDataset.m
% Prepare the completed ideal-PTO campaign for the reference AR + Hs/Tp
% study. This is a preprocessing-only stage: it does not make windows,
% select AR order, or train a neural network.
%
% Input
%   dataset_reference_ideal/run*.csv       500 audited 10-Hz source runs
%   dataset_reference_ideal/scenario_manifest.csv
%   dataset_reference_ideal/run_audit.csv
%
% Output
%   dataset_reference_ideal_5hz/run*_5hz.csv
%       time + six measured response signals only. Labels are deliberately
%       excluded, so they cannot accidentally become CNN inputs.
%   dataset_reference_ideal_5hz/source_run_index.csv
%       labels, Hs, Tp, seed and source-run split keyed by processed file.
%
% Scientific protocol
%   1. Keep only t >= 100 s, after the wave ramp.
%   2. Resample 10 Hz to 5 Hz with MATLAB resample(), which applies an
%      anti-alias low-pass filter. Do not replace this with row skipping.
%   3. Preserve the source-run train/validation/test split from the fixed
%      manifest. Windowing happens only in the next script.
 
clearvars
clc
 
thisFolder = fileparts(mfilename('fullpath'));
cd(thisFolder);
 
sourceDir = fullfile(thisFolder, 'dataset_reference_ideal');
outputDir = fullfile(thisFolder, 'dataset_reference_ideal_5hz');
 
rampTime_s = 100;
targetFs_Hz = 5;
expectedRawFs_Hz = 10;
antiAliasPassband_Hz = 2.0;
minimumLowFrequencyEnergyFraction = 0.99;
 
manifestPath = fullfile(sourceDir, 'scenario_manifest.csv');
auditPath = fullfile(sourceDir, 'run_audit.csv');
indexPath = fullfile(outputDir, 'source_run_index.csv');
 
if ~isfolder(sourceDir)
    error('prepareReferenceARDataset:missingSourceDirectory', ...
        'Cannot find %s. Complete the 500-run campaign first.', sourceDir);
end
 
if ~isfile(manifestPath) || ~isfile(auditPath)
    error('prepareReferenceARDataset:missingCampaignFiles', ...
        'scenario_manifest.csv and run_audit.csv are both required.');
end
 
if exist('resample', 'file') ~= 2 || exist('pwelch', 'file') ~= 2
    error('prepareReferenceARDataset:missingResample', ...
        ['MATLAB resample() and pwelch() are required for the ', ...
         'anti-aliased 10-to-5-Hz conversion and spectral check. ', ...
         'Install/enable Signal Processing Toolbox.']);
end
 
manifest = readtable(manifestPath);
audit = readtable(auditPath);
 
localRequireVariables(manifest, ...
    {'runID','stateName','Hs','Tp','phaseSeed','split','faultName','severity'});
localRequireVariables(audit, {'runID','csvPath','completed'});
 
if height(manifest) ~= 500 || height(audit) ~= 500
    error('prepareReferenceARDataset:wrongCampaignSize', ...
        'Expected exactly 500 manifest rows and 500 audit rows.');
end
 
audit.completed = localToLogical(audit.completed);
 
if ~all(audit.completed)
    error('prepareReferenceARDataset:incompleteCampaign', ...
        'The source campaign is incomplete: %d of 500 runs are complete.', ...
        nnz(audit.completed));
end
 
if ~isequal(sort(manifest.runID), (1:500)') || ...
        ~isequal(sort(audit.runID), (1:500)')
    error('prepareReferenceARDataset:invalidRunIDs', ...
        'Manifest and audit must each contain run IDs 1 through 500 exactly once.');
end
 
ratio = expectedRawFs_Hz / targetFs_Hz;
if abs(ratio - round(ratio)) > eps
    error('prepareReferenceARDataset:nonIntegerResamplingRatio', ...
        'The configured sampling-rate ratio must be an integer.');
end
downsampleFactor = round(ratio);
 
if ~isfolder(outputDir)
    mkdir(outputDir);
end
 
nRuns = height(manifest);
runIDOut = zeros(nRuns, 1);
stateNameOut = strings(nRuns, 1);
HsOut = zeros(nRuns, 1);
TpOut = zeros(nRuns, 1);
phaseSeedOut = zeros(nRuns, 1);
splitOut = strings(nRuns, 1);
faultNameOut = strings(nRuns, 1);
severityOut = zeros(nRuns, 1);
sourceFileOut = strings(nRuns, 1);
processedFileOut = strings(nRuns, 1);
nRawSamplesOut = zeros(nRuns, 1);
nPostRampSamplesOut = zeros(nRuns, 1);
nPreparedSamplesOut = zeros(nRuns, 1);
rawFsOut = zeros(nRuns, 1);
preparedFsOut = zeros(nRuns, 1);
lowFrequencyEnergyFraction = zeros(nRuns, 6);
 
requiredRawSignals = {'time_s','surge_m','heave_m','pitch_rad', ...
    'relDisp_m','relVel_mps','ptoForce_N','runID','phaseSeed', ...
    'severity','Hs','Tp','faultName'};
 
fprintf('\nPreparing AR dataset: 500 ideal PTO source runs\n');
fprintf('Ramp removal: t >= %.1f s | resampling: %.1f Hz -> %.1f Hz\n\n', ...
    rampTime_s, expectedRawFs_Hz, targetFs_Hz);
 
for planRow = 1:nRuns
 
    runID = manifest.runID(planRow);
    auditRow = find(audit.runID == runID, 1, 'first');
 
    sourcePath = localResolveSourcePath( ...
        audit.csvPath(auditRow), sourceDir, runID);
 
    raw = readtable(sourcePath);
    localRequireVariables(raw, requiredRawSignals);
    localValidateRawMetadata(raw, manifest(planRow, :), sourcePath);
 
    t = raw.time_s;
    localValidateTimeBase(t, expectedRawFs_Hz, sourcePath);
 
    postRamp = t >= rampTime_s;
    if nnz(postRamp) < 2 * downsampleFactor
        error('prepareReferenceARDataset:tooShortAfterRamp', ...
            'Run %d has too few samples after the ramp.', runID);
    end
 
    tPostRamp = t(postRamp);
    XpostRamp = [ ...
        raw.surge_m(postRamp), ...
        raw.heave_m(postRamp), ...
        raw.pitch_rad(postRamp), ...
        raw.relDisp_m(postRamp), ...
        raw.relVel_mps(postRamp), ...
        raw.ptoForce_N(postRamp)];
 
    if any(~isfinite(XpostRamp(:)))
        error('prepareReferenceARDataset:nonFiniteSignal', ...
            'Run %d has NaN or Inf in one of the six measured signals.', runID);
    end
 
    % Validate the downsampling decision. At least 99%% of each signal's
    % estimated post-ramp spectral energy must lie at or below 2 Hz, which
    % is safely inside the 2.5-Hz Nyquist frequency of the 5-Hz output.
    lowFrequencyEnergyFraction(planRow, :) = ...
        localLowFrequencyEnergyFraction( ...
        XpostRamp, expectedRawFs_Hz, antiAliasPassband_Hz);
 
    % resample() anti-alias filters and compensates the filter delay.
    Xprepared = zeros(ceil(size(XpostRamp, 1) / downsampleFactor), 6);
    for channel = 1:6
        Xprepared(:, channel) = resample( ...
            XpostRamp(:, channel), 1, downsampleFactor);
    end
 
    % The output samples align with the first input sample for integer
    % downsampling. Trim defensively in case MATLAB version details differ.
    tPrepared = tPostRamp(1:downsampleFactor:end);
    nPrepared = min(numel(tPrepared), size(Xprepared, 1));
    tPrepared = tPrepared(1:nPrepared);
    Xprepared = Xprepared(1:nPrepared, :);
 
    localValidatePreparedTimeBase(tPrepared, targetFs_Hz, sourcePath);
 
    [~, sourceBaseName, ~] = fileparts(sourcePath);
    processedFile = sprintf('%s_5hz.csv', sourceBaseName);
    processedPath = fullfile(outputDir, processedFile);
 
    if isfile(processedPath)
        localValidateExistingPreparedFile(processedPath, nPrepared, targetFs_Hz);
        fprintf('Skipping existing prepared file %03d/500: %s\n', ...
            runID, processedFile);
    else
        prepared = table( ...
            tPrepared, Xprepared(:,1), Xprepared(:,2), Xprepared(:,3), ...
            Xprepared(:,4), Xprepared(:,5), Xprepared(:,6), ...
            'VariableNames', {'time_s','surge_m','heave_m','pitch_rad', ...
            'relDisp_m','relVel_mps','ptoForce_N'});
 
        writetable(prepared, processedPath);
        fprintf('Prepared %03d/500: %s (%d samples)\n', ...
            runID, processedFile, nPrepared);
    end
 
    runIDOut(planRow) = runID;
    stateNameOut(planRow) = string(manifest.stateName(planRow));
    HsOut(planRow) = manifest.Hs(planRow);
    TpOut(planRow) = manifest.Tp(planRow);
    phaseSeedOut(planRow) = manifest.phaseSeed(planRow);
    splitOut(planRow) = string(manifest.split(planRow));
    faultNameOut(planRow) = string(manifest.faultName(planRow));
    severityOut(planRow) = manifest.severity(planRow);
    [~, sourceName, sourceExtension] = fileparts(sourcePath);
    sourceFileOut(planRow) = string(sprintf('%s%s', ...
    char(sourceName), char(sourceExtension)));
    processedFileOut(planRow) = string(processedFile);
    nRawSamplesOut(planRow) = height(raw);
    nPostRampSamplesOut(planRow) = nnz(postRamp);
    nPreparedSamplesOut(planRow) = nPrepared;
    rawFsOut(planRow) = expectedRawFs_Hz;
    preparedFsOut(planRow) = targetFs_Hz;
end
 
sourceRunIndex = table( ...
    runIDOut, stateNameOut, HsOut, TpOut, phaseSeedOut, splitOut, ...
    faultNameOut, severityOut, sourceFileOut, processedFileOut, ...
    nRawSamplesOut, nPostRampSamplesOut, nPreparedSamplesOut, ...
    rawFsOut, preparedFsOut, ...
    lowFrequencyEnergyFraction(:,1), lowFrequencyEnergyFraction(:,2), ...
    lowFrequencyEnergyFraction(:,3), lowFrequencyEnergyFraction(:,4), ...
    lowFrequencyEnergyFraction(:,5), lowFrequencyEnergyFraction(:,6), ...
    'VariableNames', {'runID','stateName','Hs','Tp','phaseSeed','split', ...
    'faultName','severity','sourceFile','processedFile','nRawSamples', ...
    'nPostRampSamples','nPreparedSamples','rawFs_Hz','preparedFs_Hz', ...
    'surgeEnergyAtOrBelow2Hz','heaveEnergyAtOrBelow2Hz', ...
    'pitchEnergyAtOrBelow2Hz','relDispEnergyAtOrBelow2Hz', ...
    'relVelEnergyAtOrBelow2Hz','ptoForceEnergyAtOrBelow2Hz'});
 
writetable(sourceRunIndex, indexPath);
 
assert(all(sourceRunIndex.nRawSamples == 20001), ...
    'Expected 20,001 raw samples per source run.');
assert(all(sourceRunIndex.nPostRampSamples == 19001), ...
    'Expected 19,001 post-ramp samples per source run.');
assert(all(sourceRunIndex.nPreparedSamples == 9501), ...
    'Expected 9,501 prepared samples per source run at 5 Hz.');
assert(sum(sourceRunIndex.split == "train") == 300, 'Incorrect training split.');
assert(sum(sourceRunIndex.split == "validation") == 100, 'Incorrect validation split.');
assert(sum(sourceRunIndex.split == "test") == 100, 'Incorrect test split.');
 
worstLowFrequencyEnergyFraction = min(lowFrequencyEnergyFraction(:));
fprintf('Lowest signal energy fraction at or below %.1f Hz: %.5f\n', ...
    antiAliasPassband_Hz, worstLowFrequencyEnergyFraction);
 
if worstLowFrequencyEnergyFraction < minimumLowFrequencyEnergyFraction
    error('prepareReferenceARDataset:downsamplingNotJustified', ...
        ['Less than %.1f%% of a signal''s energy is at or below %.1f Hz. ', ...
         'Keep the raw 10-Hz sampling rate and investigate that signal.'], ...
        100 * minimumLowFrequencyEnergyFraction, antiAliasPassband_Hz);
end
 
fprintf('\n====================================================\n');
fprintf('AR preprocessing complete.\n');
fprintf('Prepared runs: %d\n', height(sourceRunIndex));
fprintf('Output samples per run: %d at %.1f Hz\n', ...
    sourceRunIndex.nPreparedSamples(1), targetFs_Hz);
fprintf('Source-run index: %s\n', indexPath);
fprintf('No windows, AR coefficients, or neural-network inputs were created yet.\n');
fprintf('====================================================\n');
 
function localRequireVariables(T, requiredNames)
    missing = requiredNames(~ismember(requiredNames, T.Properties.VariableNames));
    if ~isempty(missing)
        error('prepareReferenceARDataset:missingVariable', ...
            'Required table variable(s) missing: %s', strjoin(missing, ', '));
    end
end
 
function values = localToLogical(values)
    if islogical(values)
        return
    end
    if isnumeric(values)
        values = values ~= 0;
        return
    end
    values = lower(string(values));
    if any(~ismember(values, ["true","false","1","0"]))
        error('prepareReferenceARDataset:invalidCompletionFlag', ...
            'The completed column contains values other than true/false.');
    end
    values = values == "true" | values == "1";
end
 
function sourcePath = localResolveSourcePath(auditPathValue, sourceDir, runID)
    sourcePath = string(auditPathValue);
    if ~ismissing(sourcePath) && strlength(sourcePath) > 0 && isfile(sourcePath)
        return
    end
 
    candidates = dir(fullfile(sourceDir, sprintf('run%05d_*.csv', runID)));
    if numel(candidates) ~= 1
        error('prepareReferenceARDataset:sourceFileNotFound', ...
            'Expected exactly one source CSV for run %d in %s.', runID, sourceDir);
    end
    sourcePath = string(fullfile(candidates(1).folder, candidates(1).name));
end
 
function localValidateRawMetadata(raw, planned, sourcePath)
    tolerance = 1e-12;
 
    numericNames = {'runID','phaseSeed','severity','Hs','Tp'};
    plannedNames = {'runID','phaseSeed','severity','Hs','Tp'};
    for k = 1:numel(numericNames)
        x = raw.(numericNames{k});
        expected = planned.(plannedNames{k})(1);
        if any(~isfinite(x)) || any(abs(x - expected) > tolerance)
            error('prepareReferenceARDataset:metadataMismatch', ...
                'Raw %s metadata does not match the manifest: %s', ...
                numericNames{k}, sourcePath);
        end
    end
 
    if any(string(raw.faultName) ~= string(planned.faultName(1)))
        error('prepareReferenceARDataset:metadataMismatch', ...
            'Raw faultName does not match the manifest: %s', sourcePath);
    end
end
 
function localValidateTimeBase(t, expectedFs, sourcePath)
    if any(~isfinite(t)) || any(diff(t) <= 0)
        error('prepareReferenceARDataset:invalidTime', ...
            'Time must be finite and strictly increasing: %s', sourcePath);
    end
 
    dt = diff(t);
    fs = 1 / median(dt);
    if max(abs(dt - median(dt))) > 1e-9 || abs(fs - expectedFs) > 1e-9
        error('prepareReferenceARDataset:unexpectedSamplingRate', ...
            'Expected a uniform %.1f-Hz source time base: %s', expectedFs, sourcePath);
    end
end
 
function localValidatePreparedTimeBase(t, expectedFs, sourcePath)
    if numel(t) < 2 || any(~isfinite(t)) || any(diff(t) <= 0)
        error('prepareReferenceARDataset:invalidPreparedTime', ...
            'Prepared time base is invalid: %s', sourcePath);
    end
 
    dt = diff(t);
    fs = 1 / median(dt);
    if max(abs(dt - median(dt))) > 1e-9 || abs(fs - expectedFs) > 1e-9
        error('prepareReferenceARDataset:unexpectedPreparedRate', ...
            'Prepared output is not uniformly %.1f Hz: %s', expectedFs, sourcePath);
    end
end
 
function localValidateExistingPreparedFile(processedPath, expectedRows, expectedFs)
    existing = readtable(processedPath);
    localRequireVariables(existing, {'time_s','surge_m','heave_m','pitch_rad', ...
        'relDisp_m','relVel_mps','ptoForce_N'});
 
    if height(existing) ~= expectedRows
        error('prepareReferenceARDataset:existingPreparedLengthMismatch', ...
            'Existing file has an unexpected row count: %s', processedPath);
    end
 
    localValidatePreparedTimeBase(existing.time_s, expectedFs, processedPath);
end
 
function fraction = localLowFrequencyEnergyFraction(X, fs, passbandHz)
    nSignals = size(X, 2);
    fraction = zeros(1, nSignals);
 
    for signalIndex = 1:nSignals
        [powerSpectrum, frequencyHz] = pwelch(X(:, signalIndex), [], [], [], fs);
        totalEnergy = trapz(frequencyHz, powerSpectrum);
        keep = frequencyHz <= passbandHz;
        retainedEnergy = trapz(frequencyHz(keep), powerSpectrum(keep));
 
        if totalEnergy <= eps
            fraction(signalIndex) = 1;
        else
            fraction(signalIndex) = retainedEnergy / totalEnergy;
        end
    end
end