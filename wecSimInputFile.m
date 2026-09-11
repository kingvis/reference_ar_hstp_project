% wecSimInputFile.m
% Ideal passive-PTO input file for the reference AR + Hs/Tp study.
% No friction, nonlinear damping, saturation, sensor model, or PTO-force feedback.

%% Simulation settings
simu = simulationClass();
simu.simMechanicsFile = 'RM3.slx';
simu.mode = 'normal';
simu.explorer = 'off';
simu.startTime = 0;
simu.rampTime = 100;
simu.endTime = 2000;
simu.solver = 'ode4';
simu.dt = 0.1;

%% Scenario values supplied by runReferenceCalibration.m
% Later, runReferenceIdealCampaign.m will supply the same variables.
global Hs Tp faultName severity phaseSeed

if isempty(Hs);        Hs = 1.6;                 end
if isempty(Tp);        Tp = 7.2;                 end
if isempty(faultName); faultName = 'healthy';    end
if isempty(severity);  severity = 1.0;           end
if isempty(phaseSeed); phaseSeed = 1;            end

validateattributes(Hs, {'numeric'}, {'scalar','positive','finite'});
validateattributes(Tp, {'numeric'}, {'scalar','positive','finite'});
validateattributes(severity, {'numeric'}, {'scalar','>',0,'<=',1,'finite'});
validateattributes(phaseSeed, {'numeric'}, {'scalar','integer','positive','finite'});

%% Irregular JONSWAP waves
waves = waveClass('irregular');
waves.height = Hs;
waves.period = Tp;
waves.spectrumType = 'JS';
waves.gamma = 3.3;
waves.phaseSeed = phaseSeed;

%% RM3 float body
body(1) = bodyClass('hydroData/rm3.h5');
body(1).geometryFile = 'geometry/float.stl';
body(1).mass = 'equilibrium';
body(1).inertia = [20907301 21306090.66 37085481.11];

%% RM3 spar/plate body
body(2) = bodyClass('hydroData/rm3.h5');
body(2).geometryFile = 'geometry/plate.stl';
body(2).mass = 'equilibrium';
body(2).inertia = [94419614.57 94407091.24 28542224.82];

%% Constraint
constraint(1) = constraintClass('Constraint1');
constraint(1).location = [0 0 0];

%% Ideal passive PTO
Bnom = 1.2e6;                       % healthy nominal damping, N*s/m

pto(1) = ptoClass('PTO1');
pto(1).stiffness = 0;
pto(1).damping = Bnom;              % start healthy
pto(1).location = [0 0 0];

% Apply the requested remaining-damping fraction.
% For severity 0.60, actual damping becomes 720,000 N*s/m.
pto = injectFault(pto, faultName, severity);

fprintf(['REFERENCE IDEAL PTO | fault=%s | remaining damping=%.2f | ', ...
    'applied B=%.0f N*s/m | Hs=%.2f m | Tp=%.2f s | seed=%d\n'], ...
    faultName, severity, pto(1).damping, Hs, Tp, phaseSeed);