% High fidelity PSA process model to perform CO2 purity-recovery or energy
% - productivity optimisations
clear all; close all; clc

% Load in path dependencies and .mat files
addpath('GA_files'); 
addpath('CycleSteps');
addpath('opt_results');
addpath('sorted_material_dataframes\'); % csv files containing the material input data
load('CL1_MOFs.mat');

myFolder = sprintf('%s/sorted_material_dataframes/',pwd);
filePattern = fullfile(myFolder, '*.csv');
theFiles = dir(filePattern);
for k = 1 : length(theFiles)
    baseFileName = theFiles(k).name;
    fullFileName = fullfile(theFiles(k).folder, baseFileName);
    FF_dfs{k} = readtable(fullFileName);
end


for material = 1
    material_name = alwaysDOE{material,1};
    disp(material_name)
    folder_name=[material_name, 'opt'];  % new folder name
    mkdir(folder_name)                   % create new folder

    for FF = 1:1
        N = 10;     
        type = 'EconomicEvaluation'; % alternatively choose EconomicEvaluation
        data = FF_dfs{FF};
        material_data = table2array(data(strcmp(data.material,material_name),2:15));
        FF_name       = data(strcmp(data.material,material_name),:).Forcefield{1};
        m = material_data(3:end);
        disp(m)
        % Isotherm params must be in units of Pa for b0 parameters, deltaH
        % must also be negative J/mol, 0 flag at the end indicates the
        % isotherm parameters are in units of pressure and not
        % concentration
        IsothermParams = [m(1:2),m(3:4).*1e-5,-m(5:6),m(7:8),m(9:10).*1e-5,-m(11:12),0];
        
        ro_crys     = material_data(1);      % Crystal density (kg/m3)       8
        C_ps        = material_data(2);      % Specific Cp of adsorbent (J/kg/K)    9
        material_property = [ro_crys,C_ps];
        
        %% Perform Process Optimisation
        Function = @(x) PSACycleSimulation( x, IsothermParams, material_property,[], type, N ) ; % Function to simulate the PSA cycle
        
        options         = nsgaopt() ;                            % create default options structure
        options.popsize = 70        ;                            % population size
        options.maxGen  = 150        ;                            % max generation, 10 gens
        
        options.vartype    = [1, 1, 1, 1, 1, 1, 1]         ;
        options.outputfile = sprintf('%s/%s/%s_%s_ProcRefined.txt',pwd,folder_name,material_name,FF_name) ;
        options.numObj  = 2 ;                                    % number of objectives
        options.numVar  = 7 ;                                    % number of design variables
        options.numCons = 3 ;                                    % number of constraints

        
        % x = [P_H, v_feed, t_feed, alpha_LR, epsilon, e_p, r_p];
        options.lb      = [1e5, 0.1, 5, 0.01, 0.35, 0.3, 0.5e-3];     % lower bound of x
        options.ub      = [4e5, 2, 300, 0.25, 0.45, 0.7, 1.5e-3];      % upper bound of x
        options.nameObj = {'-purity','-recovery'} ;              % the objective names are showed in GUI window.
        options.objfun  = Function               ;                % objective function handle

        options.useParallel = 'yes' ;                             % parallel computation is non-essential here
        options.poolsize     = 24   ;                              % number of worker processes
        
        result = nsga2(options)     ;                            % begin the optimization!

        [obj, vars] = sortt(loadpopfile(sprintf('%s/%s/%s_%s_ProcRefined.txt',pwd,folder_name,material_name,FF_name)));
        objectivesEcon{FF,1} = obj;
        variablesEcon{FF,1} = vars;


        savetofile(objectivesEcon,sprintf('%s/opt_results/%s_objectivesEcon.mat',pwd,material_name))
        savetofile(variablesEcon,sprintf('%s/opt_results/%s_variablesEcon.mat',pwd,material_name))

	% re-optimise for Economic Optimisation
        vars_struct = load([pwd,'/opt_results/',material_name,'_variablesEcon.mat']);
        vars_df = vars_struct.data; % load in ANN Pareto data to use as initial seed        

        N = 30 ;
        Function = @(x) PSACycleSimulation( x, IsothermParams, material_property,[], type, N ) ; % Function to simulate the PSA cycle
        options.objfun     = Function           ;                % objective function handle
        options.maxGen     = 50                ;                 % populaion size
        options.outputfile = sprintf('%s/%s/%s_%s_ProcRefined_2.txt',pwd,folder_name,material_name,FF_name) ;        ;
        vars = vars_df{FF,1};                                    % only using data from the first random seed
        options.initfun={@Pop_Override, vars}   ; 
        result2            = nsga2(options)     ;                % begin the optimization!



    end
end

function savetofile(data,fullfilename)
    save(fullfilename,'data');
end
