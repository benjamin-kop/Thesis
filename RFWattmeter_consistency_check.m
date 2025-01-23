%=========================================================================%
%           RF Wattmeter Validation Script (for single wattmeter)         %
%=========================================================================%
% Author: Benjamin Kop 
% Date last edited: 11-06-2023
clear;clc

%% Establish connection with TPO
path = '~/Documents/followingM1/RepeTUS/'; % manually indicate path 
[NeuroFUS] = NFOpen('COM7'); % manually indicate appropriate COM port for TPO
RFCOM = 'COM6'; % manually indicate appropriate COM port for RF Wattmeter
addpath(genpath(path)); % add paths 


%% Set stimulation parameters
global_power = "3600"; % input W max Power/Ch (top left TPO gui) for desired Isppa
fundamental_frequency = "500000"; % [Hz]
pulse_duration = "1000"; % [microseconds] 
pulse_repetition_period = "2000"; % [microseconds]
sonication_duration = "300000000"; % [microseconds], 5 minutes
focus = "52400"; % [micrometers]

% Remind user to select correct transducer in TPO GUI
screenSize = get(0, 'ScreenSize');                                          % get screen size
dialogPos = [(screenSize(3)-400)/2, (screenSize(4)-150)/2, 400, 150];       % set dialog position 
d = dialog('Position',dialogPos,'Name','REMINDER!');
txt = uicontrol('Parent',d, 'Style','text', 'Position',[20 80 360 40],...   % display reminder message
           'String','BEFORE CLICKING OK: CHECK TRANSDUCER ON TPO GUI',...
           'FontSize',14); 
btn = uicontrol('Parent',d,'Position',[(dialogPos(3)-70)/2 20 70 25],...    % add ok buttom  
                'String','OK','Callback','delete(gcf)');
uiwait(d);                                                                  % wait for ok before continuing script 

% Set frequency 
fprintf(NeuroFUS,'%s\r',strcat('GLOBALFREQ=',fundamental_frequency)); % turn off power limits (for now)
pause(1);
params = fread(NeuroFUS,NeuroFUS.BytesAvailable); 
set_f = char(params)'

% Circumvent pulse timing errors (set very low pulse duration)
fprintf(NeuroFUS,'%s\r',strcat('BURST=20')); 
pause(.5);
params = fread(NeuroFUS,NeuroFUS.BytesAvailable); 

% Set pulse repetition period
fprintf(NeuroFUS,'%s\r',strcat('PERIOD=',pulse_repetition_period)); 
pause(.5);
params = fread(NeuroFUS,NeuroFUS.BytesAvailable); 
set_PRP = char(params)'

% Set pulse duration 
fprintf(NeuroFUS,'%s\r',strcat('BURST=',pulse_duration)); 
pause(.5);
params = fread(NeuroFUS,NeuroFUS.BytesAvailable); 
set_PD = char(params)'

% Set sonication duration 
fprintf(NeuroFUS,'%s\r',strcat('TIMER=',sonication_duration)); 
pause(.5);
params = fread(NeuroFUS,NeuroFUS.BytesAvailable); 
set_SD = char(params)'

% Set global power 
fprintf(NeuroFUS,'%s\r',strcat('GLOBALPOWER=',global_power)); 
pause(.5);
params = fread(NeuroFUS,NeuroFUS.BytesAvailable); 
set_GP = char(params)'

% Set focus 
fprintf(NeuroFUS,'%s\r',strcat('FOCUS=',focus)); 
pause(.5);
params = fread(NeuroFUS,NeuroFUS.BytesAvailable); 
set_focus = char(params)'


%% Connect to RF Wattmeter 1
RFWM_1 = serial(RFCOM);
set(RFWM_1, 'BaudRate', 115200);
set(RFWM_1, 'DataBits', 8);
set(RFWM_1, 'StopBits', 1);
set(RFWM_1,'Terminator','CR/LF');
set(RFWM_1, 'Parity', 'none');
fopen(RFWM_1);
pause(5)


%% Start sonication
fprintf(NeuroFUS,'%s\r','START'); % send the data to the device.
pause(0.5);
params = fread(NeuroFUS,NeuroFUS.BytesAvailable); % read the data in response.


%% Read from multiple channels with single Wattmeter 
nChannel = input('Indicate which channels you want to measure from (e.g., [1], [1:4]): ');  

for channel = nChannel
    
    for j = 1:3 % take three measurements
        fprintf(RFWM_1, '%s\r', 'ALL?'); % request P, V, and A 
        pause(5) % give RF Wattmeter time 
        params = fread(RFWM_1, RFWM_1.BytesAvailable, 'char'); % read P, V, and A
        params = char(params'); % convert to characters
        values = regexp(params, '-?\d+\.\d+', 'match'); % extract values

        % Store values for P, V, and A 
        V(j) = str2double(values{1});
        A(j) = str2double(values{2});
        P(j) = str2double(values{3});

    end

    T = table(V, A, P); % Create a table with the raw values 
    
    % Create table with average values over three measurements 
    if channel == nChannel(1) 
        RFoutput = table([mean(T.V);mean(T.A);mean(T.P)],'VariableNames',{strcat('UCL_CH',num2str(channel))}); % Calculate average for each measure
    else 
        RFoutput = cat(2,RFoutput, ... 
            table([mean(T.V);mean(T.A);mean(T.P)],'VariableNames',{strcat('UCL_CH',num2str(channel))}));
    end 
    
    % Wait for user to switch RF Wattmeter to next channel 
    message = strcat(['Measurement of channel ',num2str(channel),' complete. Connect RF Wattmeter to next channel before clicking ok.']); 
    screenSize = get(0, 'ScreenSize');                                          % get screen size
    dialogPos = [(screenSize(3)-400)/2, (screenSize(4)-150)/2, 400, 150];       % set dialog position 
    d = dialog('Position',dialogPos,'Name','Switch RF Wattmeter measurement channel');
    txt = uicontrol('Parent',d, 'Style','text', 'Position',[20 80 360 40],...   % display reminder message
           'String',message,...
           'FontSize',14); 
    btn = uicontrol('Parent',d,'Position',[(dialogPos(3)-70)/2 20 70 25],...    % add ok buttom  
                'String','OK','Callback','delete(gcf)');
    uiwait(d)
end 


%% Close COM port(s)
pause(1)
s = instrfind('Type', 'serial');
for i = 1:length(s)
    fclose(s(i));
end
pause(1)


%% Sonic Concepts' measurements 
SCoutput = [16.5 17.9 20.96 23.45;
        0.639 0.778 0.552 0.649;
        10.23 13.62 7.90 9.63];

SCoutput = array2table(SCoutput, 'VariableNames', {'SC_CH1','SC_CH2','SC_CH3','SC_CH4'});
measurement = table(["voltage";"current";"power"],'VariableNames', {'measurement'});
validation = cat(2,measurement,RFoutput,SCoutput); 
writetable(validation,strcat(path,'/RF_measurements/validation.xlsx'));



