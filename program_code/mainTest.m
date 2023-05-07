%%
% Title: Main function for energy storage market participation simulation
% 
% Authors: 
% Xin Qin (qinxin_thu@outlook.com, xq234@cam.ac.uk), 
% Bolun Xu (bx2177@columbia.edu)
% 
% 
% Last update date: 5/6/2023
% Summary:
%   This code performs iterative energy storage market participation
%   simulations using a single bus ISO-NE system using a two-stage pooled
%   market clearing model including a 24-hour day-ahead unit commitment and
%   24 sequential hourly real-time economic dispatch.
%   - Demand scenario
%   - Wind capacity
%   - Storage cpacity
%   - Storage duration and efficiency
%   - Participation options: day-ahead, real-time, or day-ahead plus
%   real-time
%   - Wind uncertianty realization scenarios
%
%   Note: To run this code, yalmip and solver Gurobi are needed.
%         If you do not install yalmip, please decompress YALMIP-master.zip

%%
clc
clear all
close all
%% 1. Settings
% 1.1 System
T  = 24; % totl periods
Ts = 1;  % time interval between two periods (hour)
Tw = 4;  % time interval of rolling window dispatch
sys_para = load_system_data(T,5,5); % num_time, num_scenarios, num_RT

% avg demand 1.3e4 MW
% 1.2 parameters for case studies
WC      = [0.5 1 2]*1.3e4; % wind capacity and scaling factor - w
ES_PC   = [1 10 20:20:100 200:100:500 750:250:5000]; % P_real MW ES -j
WU      = (20) / 100; % 100% - i
ES_BU   = [0]; % the deviation (assume Guassian) used to consider bid uncertainty.


% 1.3 system parameter
sc_num      = 5; % number of scenarios
wind_num    = length(WC);
noise_num   = length(WU);
P_num       = length(ES_PC);
un_num      = length(ES_BU);
RT_num      = 5;
seg_num     = 1;% value function segment number, 1-power bidding, multi-SoC bidding
Pr  = 0.25;     % normalized power rating wrt energy rating
P   = Pr*Ts;    % actual power rating taking time step size into account: now 10MW/40MWh
eta = .9;       % efficiency
c   = 25;       % marginal discharge cost - degradation
ed  = .01;      % SoC sample granularity
ef  = .0;       % final SoC target level, use 0 if none
Ne  = floor(1/ed)+1; % number of SOC samples
e0  = 0;
% rho = 0.5;    % ratio of storage in DA and RT markets
is_DART = 1;    % allow or not DA+RT participation
%% Simulation
% Start iterative scenario simulation
t00 = cputime;
clear Iter

for iS = 1:5 % go through each demand scenario
    fprintf('Start scenario %d. \n',iS);
    % corresponding RT scenarios to study invarience
    for iEU = 1:un_num % go through each storage bidding strategy 
    for iRT = 1:1 % 
        % wind capacity
        for iWC = 1:wind_num % go through each wind capacity scenario
            fprintf('Running subloop %.2f %%. \n',iWC/wind_num*100);
            for iWU = 1:noise_num % go through each wind uncertainty realization scenario
                %% Initialize the simulation parameters
                Iter.mpc = prepare_power_system(sys_para, WC(iWC), WU(iWU), T, iS, iRT);
                %% Simulate the unit commitment without energy storage
                Iter.UC = DAUC_noES(Iter.mpc);
                %% Generate energy storagereal-time bids based on the UC day-ahead prices
                [VF(1), VF_all] = value_fcn_calcu(Iter.UC.LMP,seg_num, Ne, T, c, P, eta, ed, ef, ES_BU(iEU));
                for iE = 1:P_num
                    EC(iE) = ES_PC(iE)/P; % get storage duration

                    %% Perform sequential real-time economic dispatch using generated storage bids
                    fprintf('Running S-ED with P = %d. \n', ES_PC(iE));
                    Iter.SP = M_RTED(Iter.UC, Iter.mpc, e0, ES_PC(iE), EC(iE), eta, c, VF, 1, 0);

                    %% Perform sequential real-time economic dispatch without storage for reference
                    fprintf('Running N-ED with P = %d. \n', ES_PC(iE));
                    Iter.NE = M_RTED(Iter.UC, Iter.mpc, e0, 0 , 0 , eta, c, VF, 1, 0);

                    %% DA+RT participation: storage participate both in UC and ED
                    fprintf('Running DA with P = %d. \n', ES_PC(iE));
                    % perform UC with storage
                    [Iter.DADA, Iter.DART] = DAUC_wiES(Iter.mpc, e0, ES_PC(iE), EC(iE), eta, c, VF, ~is_DART);% unit commitment result with storage
                    % generate storage bids using UC day-ahead prices
                    [VFUC(1), VF_all] = value_fcn_calcu(Iter.DADA.LMP,seg_num, Ne, T, c, P, eta, ed, ef, ES_BU(iEU));
                    % perform sequential ED with storage
                    Iter.DART2 = M_RTED(Iter.DADA, Iter.mpc, e0, ES_PC(iE), EC(iE), eta, c, VFUC, 1, is_DART);% real-time dispatch result w/o storage but using DA storage schedule
                    %% Record results
                    k = (iWC-1)*P_num*noise_num + (iWU-1)*P_num + iE;
                    SC(iS).ESU(iEU).RT(iRT).Iter(k) = Iter;
                end
            end
            end
        end
    end
end
total_time = cputime-t00;
%% Save results
save('test_data.mat');

