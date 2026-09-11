%% runReferenceIdealCampaign.m
% Generate the ideal PTO reference dataset:
% 5 Indian sea states × 5 damping conditions × 20 wave seeds = 500 runs.
%
% This is a reference-paper-style study:
% - standard passive PTO in RM3.slx
% - actual WEC-Sim internal force/power exported
% - no friction, B3, saturation, noise, bias, or dropout
% - repeated random wave-phase realizations
 
clear; clc;
clear global
 
global Hs Tp faultName severity phaseSeed
 
thisFolder = fileparts(mfilename('fullpath'));
cd(thisFolder);
 
Bnom = 1.2e6;  % Healthy nominal PTO damping [N*s/m]
 
%% Indian sea-state table supplied for the study
stateName = { ...
    'State1_Calm'; ...
    'State2_Mild'; ...
    'State3_Energetic'; ...
    'State4_LongPeriodSwell'; ...
    'State5_Moderate'};
 
HsValues = [1.1; 1.5; 1.6; 1.6; 2.2];
TpValues = [8.5; 6.0; 7.2; 10.0; 8.3];
 
% Recorded for future operational weighting; NOT used to unbalance training.
stateProbability = [0.177993; 0.248189; 0.282490; 0.109868; 0.181461];
 
%% PTO damping conditions
% severity = fraction of nominal damping remaining.
severityLevels = [1.0, 0.8, 0.6, 0.4, 0.2];
 
%% Wave-phase seeds and source-run split
allPhaseSeeds = 1:20;
 
% First run only 50 cases as a smoke test: 5 states × 5 severities × 2 seeds.
% After that succeeds, change this one line to:
% seedsToSimulate = 1:20;
seedsToSimulate = 1:20;
 
if any(~ismember(seedsToSimulate, allPhaseSeeds))
    error('seedsToSimulate must contain only integers from 1 to 20.');
end
 
dataDir = fullfile(thisFolder, 'dataset_reference_ideal');
if ~exist(dataDir, 'dir')
    mkdir(dataDir);
end
 
manifestPath = fullfile(dataDir, 'scenario_manifest.csv');
auditPath = fullfile(dataDir, 'run_audit.csv');
 
%% Build the complete 500-run plan in a fixed deterministic order
nStates = numel(stateName);
nSeeds = numel(allPhaseSeeds);
nSeverities = numel(severityLevels);
nPlannedRuns = nStates * nSeeds * nSeverities;
 
runIDColumn = zeros(nPlannedRuns, 1);
stateNameColumn = cell(nPlannedRuns, 1);
HsColumn = zeros(nPlannedRuns, 1);
TpColumn = zeros(nPlannedRuns, 1);
probabilityColumn = zeros(nPlannedRuns, 1);
phaseSeedColumn = zeros(nPlannedRuns, 1);
splitColumn = cell(nPlannedRuns, 1);
faultNameColumn = cell(nPlannedRuns, 1);
severityColumn = zeros(nPlannedRuns, 1);
BfaultColumn = zeros(nPlannedRuns, 1);
 
row = 0;
 
for ss = 1:nStates
    for seed = allPhaseSeeds
 
        if seed <= 12
            splitName = 'train';
        elseif seed <= 16
            splitName = 'validation';
        else
            splitName = 'test';
        end
 
        for sev = severityLevels
            row = row + 1;
 
            if sev == 1.0
                thisFaultName = 'healthy';
            else
                thisFaultName = 'pto_damping_loss';
            end
 
            runIDColumn(row) = row;
            stateNameColumn{row} = stateName{ss};
            HsColumn(row) = HsValues(ss);
            TpColumn(row) = TpValues(ss);
            probabilityColumn(row) = stateProbability(ss);
            phaseSeedColumn(row) = seed;
            splitColumn{row} = splitName;
            faultNameColumn{row} = thisFaultName;
            severityColumn(row) = sev;
            BfaultColumn(row) = Bnom * sev;
        end
    end
end
 
plan = table( ...
    runIDColumn, stateNameColumn, HsColumn, TpColumn, probabilityColumn, ...
    phaseSeedColumn, splitColumn, faultNameColumn, severityColumn, BfaultColumn, ...
    'VariableNames', { ...
    'runID','stateName','Hs','Tp','stateProbability', ...
    'phaseSeed','split','faultName','severity','Bfault_NsPm'});
 
%% Save or verify the fixed scenario manifest
if exist(manifestPath, 'file')
    existingManifest = readtable(manifestPath);
 
    if height(existingManifest) ~= height(plan) || ...
       any(existingManifest.runID ~= plan.runID) || ...
       any(abs(existingManifest.Hs - plan.Hs) > eps) || ...
       any(abs(existingManifest.Tp - plan.Tp) > eps) || ...
       any(existingManifest.phaseSeed ~= plan.phaseSeed) || ...
       any(abs(existingManifest.severity - plan.severity) > eps)
 
        error(['Existing scenario_manifest.csv does not match this fixed ', ...
               '500-run experimental plan. Use a new output folder.']);
    end
else
    writetable(plan, manifestPath);
end
 
%% Create or resume the run audit table
if exist(auditPath, 'file')
    auditTable = readtable(auditPath);
 
    if height(auditTable) ~= nPlannedRuns
        error('Existing run_audit.csv has the wrong number of planned rows.');
    end
else
    auditTable = plan;
    auditTable.csvPath = strings(nPlannedRuns, 1);
    auditTable.expectedDamping_NsPm = BfaultColumn;
    auditTable.estimatedDamping_NsPm = nan(nPlannedRuns, 1);
    auditTable.relativeDampingError = nan(nPlannedRuns, 1);
    auditTable.forceLawMaxError_N = nan(nPlannedRuns, 1);
    auditTable.forceLawRelativeError = nan(nPlannedRuns, 1);
    auditTable.powerConsistencyError_W = nan(nPlannedRuns, 1);
    auditTable.completed = false(nPlannedRuns, 1);
    writetable(auditTable, auditPath);
end
 
% readtable can infer an all-empty csvPath column as numeric when a batch
% stops before its first completed row is written. Keep it explicitly as
% text so that resume assignments below use table row indexing correctly.
auditTable.csvPath = string(auditTable.csvPath);
 
%% Run only the selected phase seeds
selectedRows = ismember(plan.phaseSeed, seedsToSimulate);
selectedRunIDs = find(selectedRows);
 
fprintf('\nReference ideal PTO campaign\n');
fprintf('Selected seeds: %s\n', mat2str(seedsToSimulate));
fprintf('Runs selected now: %d of %d planned runs\n\n', ...
    numel(selectedRunIDs), nPlannedRuns);
 
for i = selectedRunIDs'
 
    scenario = struct;
    scenario.runID = plan.runID(i);
    scenario.faultName = plan.faultName{i};
    scenario.severity = plan.severity(i);
    scenario.Hs = plan.Hs(i);
    scenario.Tp = plan.Tp(i);
    scenario.phaseSeed = plan.phaseSeed(i);
    scenario.Bfault = plan.Bfault_NsPm(i);
 
    expectedFileName = sprintf( ...
        'run%05d_seed%03d_sev%03d_Hs%03d_Tp%03d.csv', ...
        scenario.runID, scenario.phaseSeed, ...
        round(100 * scenario.severity), ...
        round(100 * scenario.Hs), ...
        round(100 * scenario.Tp));
 
    expectedCsvPath = fullfile(dataDir, expectedFileName);
 
    % Resume safely: existing CSV is never overwritten.
    if exist(expectedCsvPath, 'file')
        if ~logical(auditTable.completed(i))
            [Bhat, relBError, maxFError, relFError, powerError] = ...
                auditExistingCsv(expectedCsvPath, scenario.Bfault);
 
            auditTable.csvPath(i) = string(expectedCsvPath);
            auditTable.estimatedDamping_NsPm(i) = Bhat;
            auditTable.relativeDampingError(i) = relBError;
            auditTable.forceLawMaxError_N(i) = maxFError;
            auditTable.forceLawRelativeError(i) = relFError;
            auditTable.powerConsistencyError_W(i) = powerError;
            auditTable.completed(i) = true;
            writetable(auditTable, auditPath);
        end
 
        fprintf('Skipping completed run %d: %s\n', scenario.runID, expectedFileName);
        continue;
    end
 
    % Put the planned scenario into the WEC-Sim input-file globals.
    Hs = scenario.Hs;
    Tp = scenario.Tp;
    faultName = scenario.faultName;
    severity = scenario.severity;
    phaseSeed = scenario.phaseSeed;
 
    fprintf('\n====================================================\n');
    fprintf(['RUN %03d/500 | %s | remaining damping %.0f%% | ', ...
             'Hs %.1f m | Tp %.1f s | seed %d | split %s\n'], ...
             scenario.runID, scenario.faultName, 100 * scenario.severity, ...
             scenario.Hs, scenario.Tp, scenario.phaseSeed, plan.split{i});
    fprintf('Expected damping = %.0f N*s/m\n', scenario.Bfault);
    fprintf('====================================================\n');
 
    clear output
    wecSim
 
    [csvPath, audit] = exportTimeSeries(output, scenario, dataDir);
 
    % WEC-Sim executes supporting scripts in this workspace and can change
    % the conventional loop variable i.  runID is deliberately identical
    % to the fixed plan/audit row and is retained in scenario.
    auditRow = scenario.runID;
    auditTable.csvPath(auditRow) = string(csvPath);
    auditTable.estimatedDamping_NsPm(auditRow) = audit.estimatedDamping_NsPm;
    auditTable.relativeDampingError(auditRow) = audit.relativeDampingError;
    auditTable.forceLawMaxError_N(auditRow) = audit.forceLawMaxError_N;
    auditTable.forceLawRelativeError(auditRow) = audit.forceLawRelativeError;
    auditTable.powerConsistencyError_W(auditRow) = audit.powerConsistencyError_W;
    auditTable.completed(auditRow) = true;
 
    % Save after every simulation, so interrupted work can resume safely.
    writetable(auditTable, auditPath);
end
 
completedCount = nnz(logical(auditTable.completed));
 
fprintf('\n====================================================\n');
fprintf('Selected batch complete.\n');
fprintf('Completed source runs: %d / %d\n', completedCount, nPlannedRuns);
fprintf('Manifest: %s\n', manifestPath);
fprintf('Audit:    %s\n', auditPath);
fprintf('====================================================\n');
 
function [Bhat, relativeBError, maxForceError, relativeForceError, powerError] = ...
    auditExistingCsv(csvPath, expectedB)
 
    T = readtable(csvPath);
    use = T.time_s >= 100;
 
    v = T.relVel_mps(use);
    F = T.ptoForce_N(use);
    P = T.ptoPower_W(use);
 
    Bhat = -sum(F .* v) / sum(v.^2);
    expectedForce = -expectedB .* v;
 
    relativeBError = abs(Bhat - expectedB) / expectedB;
    maxForceError = max(abs(F - expectedForce));
    relativeForceError = maxForceError / max(max(abs(expectedForce)), 1);
    powerError = max(abs(P - F .* v));
end