%% runBatch.m  -  Generate the labelled PTO-fault dataset  (MoorDyn OFF)
%
% Loops over 5 sea states x 5 fault conditions = 25 runs.
% For each run:  set parameters  ->  simulate  ->  save one labelled CSV.
%
% HOW IT WORKS: we set Hs, Tp, faultName, severity as GLOBALS. When wecSim
% runs wecSimInputFile.m, that file reads these globals. So we never edit the
% input file by hand - the loop changes the run for us.
 
clear; clc;
global Hs Tp faultName severity
 
% --- 5 sea states (Hs [m], Tp [s]) : PacWave-derived, from your Stage 2 ---
seaStates = [
    1.10,  8.50;   % SS1  Calm
    1.50,  6.00;   % SS2  Mild
    1.60, 7.20;   % SS3  Energetic (reference case)
    1.60, 10.00;   % SS4  Long-period swell
    2.20, 8.30;   % SS5  Moderate
];
 
% --- 5 fault conditions : 1 healthy baseline + 4 PTO severities ---
faults = {
    'healthy',          1.0;   % no fault (the "what normal looks like" baseline)
    'pto_damping_loss', 0.8;   % mild   - 80% of normal damping
    'pto_damping_loss', 0.6;   % medium - 60%
    'pto_damping_loss', 0.4;   % strong - 40%
    'pto_damping_loss', 0.2;   % severe - 20%
};
 
runID = 0;
for ss = 1:size(seaStates,1)
    Hs = seaStates(ss,1);
    Tp = seaStates(ss,2);
    for fc = 1:size(faults,1)
        faultName = faults{fc,1};
        severity  = faults{fc,2};
        runID = runID + 1;
 
        fprintf('\n=== Run %03d | %-16s sev %.2f | Hs %.2f Tp %.2f ===\n', ...
                runID, faultName, severity, Hs, Tp);
 
        wecSim;     % wecSim automatically runs wecSimInputFile.m, then simulates
                    % -> it creates the variable "output"
        exportTimeSeries(output, faultName, severity, Hs, Tp, runID);
    end
end
 
fprintf('\nAll %d runs finished. CSV files are in the dataset\\ folder.\n', runID);