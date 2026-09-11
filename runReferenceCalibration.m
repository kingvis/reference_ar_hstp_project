%% runReferenceCalibration.m
% Two-run physical validation before the 500-run ideal reference campaign.
% Uses Indian Sea State 3: Hs = 1.6 m, Tp = 7.2 s.
 
clear; clc;
clear global
 
global Hs Tp faultName severity phaseSeed
 
thisFolder = fileparts(mfilename('fullpath'));
cd(thisFolder);
 
Bnom = 1.2e6;
outputDir = fullfile(thisFolder, 'calibration_reference_ideal');
 
if exist(outputDir, 'dir') && ~isempty(dir(fullfile(outputDir, '*.csv')))
    error(['Calibration folder already has CSV files. Do not overwrite results. ' ...
           'Rename or archive the folder before repeating calibration.']);
end
 
% Same sea state and same phase seed; only PTO damping changes.
Hs = 1.6;
Tp = 7.2;
phaseSeed = 101;
 
calibrationSeverities = [1.0, 0.6];
auditRows = struct([]);
 
for k = 1:numel(calibrationSeverities)
 
    severity = calibrationSeverities(k);
 
    if severity == 1.0
        faultName = 'healthy';
    else
        faultName = 'pto_damping_loss';
    end
 
    runID = k;
 
    scenario = struct;
    scenario.runID = runID;
    scenario.faultName = faultName;
    scenario.severity = severity;
    scenario.Hs = Hs;
    scenario.Tp = Tp;
    scenario.phaseSeed = phaseSeed;
    scenario.Bfault = Bnom * severity;
 
    fprintf('\n====================================================\n');
    fprintf('CALIBRATION RUN %d | %s | remaining damping %.0f%%\n', ...
        runID, faultName, 100 * severity);
    fprintf('Expected damping: %.0f N*s/m\n', scenario.Bfault);
    fprintf('====================================================\n');
 
    clear output
    wecSim
 
    [csvPath, audit] = exportTimeSeries(output, scenario, outputDir);
 
    auditRows(k).runID = runID;
    auditRows(k).faultName = faultName;
    auditRows(k).severity = severity;
    auditRows(k).Hs = Hs;
    auditRows(k).Tp = Tp;
    auditRows(k).phaseSeed = phaseSeed;
    auditRows(k).csvPath = csvPath;
    auditRows(k).expectedDamping_NsPm = audit.expectedDamping_NsPm;
    auditRows(k).estimatedDamping_NsPm = audit.estimatedDamping_NsPm;
    auditRows(k).relativeDampingError = audit.relativeDampingError;
    auditRows(k).forceLawMaxError_N = audit.forceLawMaxError_N;
    auditRows(k).forceLawRelativeError = audit.forceLawRelativeError;
    auditRows(k).powerConsistencyError_W = audit.powerConsistencyError_W;
end
 
auditTable = struct2table(auditRows);
writetable(auditTable, fullfile(outputDir, 'calibration_audit.csv'));
 
disp(auditTable)
 
fprintf('\nCalibration complete. Review calibration_audit.csv before generating 500 runs.\n');