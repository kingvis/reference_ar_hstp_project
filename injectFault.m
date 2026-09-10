function pto = injectFault(pto, faultName, severity)
% injectFault  Apply ONE fault to the PTO, then hand the PTO back.
%
%   pto = injectFault(pto, faultName, severity)
%
%   It RETURNS the changed pto so the caller can use it.  
%
%   faultName : 'healthy'  or  'pto_damping_loss'  (alias: 'pto_fault')
%   severity  : fraction of the nominal value that REMAINS.
%               1.0 = perfectly healthy, 0.5 = half strength, 0.2 = nearly dead.
%
%   Mooring faults are intentionally left out for now because MoorDyn is
%   switched off while we focus on the PTO defect. Add them back here later.

switch faultName

    case 'healthy'
        % Do nothing - the PTO keeps its full, nominal damping.

    case {'pto_damping_loss', 'pto_fault'}
        % Worn PTO (seal wear / fluid loss): scale the damping down.
      
        pto(1).damping = pto(1).damping * severity;

    otherwise
        error('injectFault:unknownFault', ...
            'Unknown fault "%s". Use ''healthy'' or ''pto_damping_loss''.', faultName);
end
end