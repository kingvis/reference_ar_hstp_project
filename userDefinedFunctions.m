
%Plot waves
waves.plotElevation(simu.rampTime);
try 
    waves.plotSpectrum();
catch
end

%Plot heave response for body 1
output.plotResponse(1,3);

%Plot heave response for body 2
output.plotResponse(2,3);

%Plot heave forces for body 1
output.plotForces(1,3);

%Plot heave forces for body 2
output.plotForces(2,3);

%Example of user input MATLAB file for post processing
% Example minimal cable definition — put in wecSimInputFile.m or init_my_model.m
% Replace the coordinates with the correct base and follower locations for your model
cable(1).base.location     = [0, 0, -5];   % [x y z]
cable(1).follower.location = [0.5, 0, -6]; % [x y z]

% If model uses more cables, create additional entries:
% cable(2).base.location = [...]; cable(2).follower.location = [...];


%Save waves and response as video
% output.saveViz(simu,body,waves,...
%     'timesPerFrame',5,'axisLimits',[-150 150 -150 150 -50 20],...
%     'startEndTime',[100 125]);
