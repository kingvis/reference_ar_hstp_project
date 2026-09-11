function [csvPath, audit] = exportTimeSeries(output, scenario, outputDir)
% exportTimeSeries
% Export actual ideal passive-PTO measurements from WEC-Sim.
%
% This file NEVER reconstructs force or power from the severity label.
% It saves the actual PTO internal-mechanics signals from WEC-Sim.
 
if nargin < 3
    outputDir = fullfile(pwd, 'dataset_reference_ideal');
end
 
requiredFields = {'runID','faultName','severity','Hs','Tp','phaseSeed','Bfault'};
for k = 1:numel(requiredFields)
    if ~isfield(scenario, requiredFields{k})
        error('exportTimeSeries:missingScenarioField', ...
            'scenario.%s is required.', requiredFields{k});
    end
end
 
% Match all signal lengths safely.
n = min([ ...
    size(output.bodies(1).position, 1), ...
    size(output.ptos(1).position, 1), ...
    size(output.ptos(1).velocity, 1), ...
    size(output.ptos(1).forceInternalMechanics, 1), ...
    size(output.ptos(1).powerInternalMechanics, 1)]);
 
% Actual WEC-Sim measurements.
t     = output.bodies(1).time(1:n);
surge = output.bodies(1).position(1:n,1);
heave = output.bodies(1).position(1:n,3);
pitch = output.bodies(1).position(1:n,5);
 
% PTO local translational Z direction: the true PTO stroke and velocity.
relDisp = output.ptos(1).position(1:n,3);
relVel  = output.ptos(1).velocity(1:n,3);
 
% Actual passive-PTO force and power: never label-reconstructed.
ptoForce = output.ptos(1).forceInternalMechanics(1:n,3);
ptoPower = output.ptos(1).powerInternalMechanics(1:n,3);
 
if max(abs(heave)) < 1e-9
    error('exportTimeSeries:noMotion', ...
        'Run %d produced no heave motion. CSV was not written.', scenario.runID);
end
 
% Physical audit after the 100-second wave ramp.
use = t >= 100;
v = relVel(use);
F = ptoForce(use);
P = ptoPower(use);
 
if sum(v.^2) <= eps
    error('exportTimeSeries:noRelativeMotion', ...
        'Run %d has insufficient PTO relative motion for damping audit.', scenario.runID);
end
 
Bhat = -sum(F .* v) / sum(v.^2);
expectedForce = -scenario.Bfault .* v;
 
audit.expectedDamping_NsPm = scenario.Bfault;
audit.estimatedDamping_NsPm = Bhat;
audit.relativeDampingError = abs(Bhat - scenario.Bfault) / scenario.Bfault;
audit.forceLawMaxError_N = max(abs(F - expectedForce));
audit.forceLawRelativeError = audit.forceLawMaxError_N / ...
    max(max(abs(expectedForce)), 1);
audit.powerConsistencyError_W = max(abs(P - F .* v));
audit.nSamples = n;
 
if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end
 
nRows = numel(t);
T = table( ...
    t, surge, heave, pitch, relDisp, relVel, ptoForce, ptoPower, ...
    repmat({char(scenario.faultName)}, nRows, 1), ...
    repmat(scenario.severity, nRows, 1), ...
    repmat(scenario.Hs, nRows, 1), ...
    repmat(scenario.Tp, nRows, 1), ...
    repmat(scenario.runID, nRows, 1), ...
    repmat(scenario.phaseSeed, nRows, 1), ...
    repmat(scenario.Bfault, nRows, 1), ...
    'VariableNames', { ...
    'time_s','surge_m','heave_m','pitch_rad', ...
    'relDisp_m','relVel_mps','ptoForce_N','ptoPower_W', ...
    'faultName','severity','Hs','Tp','runID','phaseSeed','Bfault_NsPm'});
 
fileName = sprintf( ...
    'run%05d_seed%03d_sev%03d_Hs%03d_Tp%03d.csv', ...
    scenario.runID, scenario.phaseSeed, ...
    round(100 * scenario.severity), ...
    round(100 * scenario.Hs), ...
    round(100 * scenario.Tp));
 
csvPath = fullfile(outputDir, fileName);
 
if exist(csvPath, 'file')
    error('exportTimeSeries:fileExists', ...
        'Refusing to overwrite existing file: %s', csvPath);
end
 
writetable(T, csvPath);
 
fprintf(['Saved %s\n', ...
         '  B expected = %.6f N*s/m | B estimated = %.6f N*s/m | rel. error = %.3e\n', ...
         '  force-law error = %.3e N | power-consistency error = %.3e W\n'], ...
         csvPath, audit.expectedDamping_NsPm, audit.estimatedDamping_NsPm, ...
         audit.relativeDampingError, audit.forceLawMaxError_N, ...
         audit.powerConsistencyError_W);
end