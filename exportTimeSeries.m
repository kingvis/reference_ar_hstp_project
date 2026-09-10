function exportTimeSeries(output, faultName, severity, Hs, Tp, runID)
% exportTimeSeries  Write ONE labelled CSV for a single WEC-Sim run.
%
%   Columns:  time + float motions + PTO stroke/force/power + 5 label columns.
%   It first checks that the buoy actually moved; if every value is zero it
%   refuses to save (so you never  get a silent all-zero file).
 
    %% 1. Pull the signals straight out of the output object
    t     = output.bodies(1).time;
    surge = output.bodies(1).position(:,1);   % column 1 = surge
    heave = output.bodies(1).position(:,3);   % column 3 = heave
    pitch = output.bodies(1).position(:,5);   % column 5 = pitch
 
    % PTO stroke = float heave minus spar heave (how much the damper extends)
    relDisp = output.bodies(1).position(:,3) - output.bodies(2).position(:,3);
    relVel  = output.bodies(1).velocity(:,3) - output.bodies(2).velocity(:,3);
 
    %% 2. PTO force & power for a linear damper:  F = c*v ,  P = F*v
    cNominal = 1200000;                 % MUST match pto(1).c in wecSimInputFile.m
    cApplied = cNominal;
    if any(strcmp(faultName, {'pto_damping_loss','pto_fault'}))
        cApplied = cNominal * severity; % the faulted damping that was really used
    end
    ptoForce = cApplied .* relVel;
    ptoPower = ptoForce .* relVel;
 
    %% 3. SAFETY CHECK - did the buoy actually move?
    if max(abs(heave)) < 1e-9
        warning('exportTimeSeries:emptyRun', ...
            ['Run %d (%s, sev %.2f, Hs %.2f, Tp %.2f) produced NO motion. ', ...
             'The simulation did not really run - CSV NOT saved.'], ...
             runID, faultName, severity, Hs, Tp);
        return;                          % do not save garbage
    end
 
    %% 4. Label columns (same value repeated on every row)
    n = numel(t);
    T = table( t, surge, heave, pitch, relDisp, relVel, ptoForce, ptoPower, ...
               repmat({faultName}, n, 1), ...
               repmat(severity,    n, 1), ...
               repmat(Hs,          n, 1), ...
               repmat(Tp,          n, 1), ...
               repmat(runID,       n, 1), ...
        'VariableNames', { 'time_s','surge_m','heave_m','pitch_rad', ...
                           'relDisp_m','relVel_mps','ptoForce_N','ptoPower_W', ...
                           'faultName','severity','Hs','Tp','runID' });
 
    %% 5. Save into a dataset folder with a self-describing name
    if ~exist('dataset','dir'); mkdir('dataset'); end
    fname = sprintf('dataset/run%03d_%s_sev%03d_Hs%03d_Tp%03d.csv', ...
                    runID, faultName, round(severity*100), round(Hs*100), round(Tp*100));
    writetable(T, fname);
    fprintf('  saved %s  (%d rows)\n', fname, n);
end