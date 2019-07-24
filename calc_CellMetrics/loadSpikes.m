function spikes = loadSpikes(varargin)
% Load clustered data from multiple pipelines [Current options: Phy, Klustakwik/Neurosuite,klustaViewa]
% Buzcode compatible output. Saves output to a basename.spikes.cellinfo.mat file
%
% INPUTS
%
% See description of varargin below
%
% OUTPUT
%
% spikes:               - Matlab struct following the buzcode standard (https://github.com/buzsakilab/buzcode)
%     .sessionName      - Name of recording file
%     .UID              - Unique identifier for each neuron in a recording
%     .times            - Cell array of timestamps (seconds) for each neuron
%     .spindices        - Sorted vector of [spiketime UID], useful as input to some functions and plotting rasters
%     .region           - Region ID for each neuron (especially important large scale, high density probes)
%     .maxWaveformCh    - Channel # with largest amplitude spike for each neuron (0-indexed)
%     .maxWaveformCh1   - Channel # with largest amplitude spike for each neuron (1-indexed)
%     .rawWaveform      - Average waveform on maxWaveformCh (from raw .dat)
%     .filtWaveform     - Average filtered waveform on maxWaveformCh (from raw .dat)
%     .rawWaveform_std  - Average waveform on maxWaveformCh (from raw .dat)
%     .filtWaveform_std - Average filtered waveform on maxWaveformCh (from raw .dat)
%     .peakVoltage      - Peak voltage (uV)
%     .cluID            - Cluster ID
%     .shankID          - shankID
%     .processingInfo   - Processing info
%
% DEPENDENCIES: 
%
% LoadXml.m & xmltools.m (default) or bz_getSessionInfo.m

% By Peter Petersen
% petersen.peter@gmail.com
% Last edited: 20-06-2019

% Version history
% 3.2 waveforms for phy data extracted from the raw dat
% 3.3 waveforms extracted from raw dat using memmap function. Interval and bad channels bugs fixed as well
% 3.4 bug fix which gave misaligned waveform extraction from raw dat. Plot improvements of waveforms
% 3.5 new name and better handling of inputs

p = inputParser;
addParameter(p,'basepath',pwd,@ischar); % basepath with dat file, used to extract the waveforms from the dat file
addParameter(p,'clusteringpath','',@ischar); % clustering path to spike data
addParameter(p,'clusteringformat','Phy',@ischar); % clustering format: [Current options: Phy, Klustakwik/Neurosuite,klustaViewa]
addParameter(p,'basename','',@ischar); % The baseName file naming convention
addParameter(p,'shanks',nan,@isnumeric); % shanks: Loading only a subset of shanks (only applicable to Klustakwik)
addParameter(p,'raw_clusters',false,@islogical); % raw_clusters: Load only a subset of clusters (might not work anymore as it has not been tested for a long time)
addParameter(p,'saveMat',true,@islogical); % Save spikes to mat file?
addParameter(p,'forceReload',false,@islogical); % Reload spikes from original format (overwrites existing mat file if saveMat==true)
addParameter(p,'getWaveforms',true,@islogical); % Get average waveforms?
addParameter(p,'useNeurosuiteWaveforms',false,@islogical); % Use Waveform features from spk files. Alternatively it loads waveforms from dat file (Klustakwik specific)
addParameter(p,'spikes',[],@isstruct); % Load existing spikes structure to append new spike info
addParameter(p,'LSB',0.195,@isnumeric); % Least significant bit (LSB in uV) Intan = 0.195, Amplipex = 0.3815. (range/precision)
addParameter(p,'session',[],@isstruct); % A buzsaki lab db session struct
addParameter(p,'buzcode',false,@islogical); % If true, uses bz_getSessionInfo. Otherwise uses LoadXml


parse(p,varargin{:})

basepath = p.Results.basepath;
clusteringPath = p.Results.clusteringpath;
clusteringFormat = p.Results.clusteringformat;
baseName = p.Results.basename;
shanks = p.Results.shanks;
raw_clusters = p.Results.raw_clusters;
forceReload = p.Results.forceReload;
saveMat = p.Results.saveMat;
getWaveforms = p.Results.getWaveforms;
spikes = p.Results.spikes;
useNeurosuiteWaveforms = p.Results.useNeurosuiteWaveforms;
LSB = p.Results.LSB;
session = p.Results.session;

buzcode = p.Results.buzcode;

if isempty(baseName) & ~isempty(basepath)
    [~,baseName,~] = fileparts(basepath);
    disp(['Using basepath to determine the basename: ' baseName])
end

if exist(fullfile(clusteringPath,[baseName,'.spikes.cellinfo.mat'])) & ~forceReload
    load(fullfile(clusteringPath,[baseName,'.spikes.cellinfo.mat']))
    if isfield(spikes,'ts') && (~isfield(spikes,'processinginfo') || (isfield(spikes,'processinginfo') && spikes.processinginfo.version < 3 && strcmp(spikes.processinginfo.function,'loadSpikes') ))
        forceReload = true;
        disp('spikes.mat structure not up to date. Reloading spikes.')
    else
        disp('loadSpikes: Loading existing spikes file')
    end
else
    forceReload = true;
end

% Loading spikes
if forceReload
    % Loading session info
    if buzcode
        xml = bz_getSessionInfo(basepath, 'noPrompts', true);
        xml.SampleRate = xml.rates.wideband;
    else
        xml = LoadXml(fullfile(clusteringPath,[baseName, '.xml']));
    end
    switch lower(clusteringFormat)
        
        % Loading klustakwik
        case {'klustakwik', 'neurosuite'}
            disp('loadSpikes: Loading Klustakwik data')
            unit_nb = 0;
            spikes = [];
            shanks_new = [];
            if isnan(shanks)
                fileList = dir(fullfile(clusteringPath,[baseName,'.res.*']));
                fileList = {fileList.name};
                for i = 1:length(fileList)
                    temp = strsplit(fileList{i},'.res.');
                    shanks_new = [shanks_new,str2num(temp{2})];
                end
                shanks = sort(shanks_new);
            end
            for shank = shanks
                disp(['Loading shank #' num2str(shank) '/' num2str(length(shanks)) ])
                if ~raw_clusters
                    cluster_index = load(fullfile(clusteringPath, [baseName '.clu.' num2str(shank)]));
                    time_stamps = load(fullfile(clusteringPath,[baseName '.res.' num2str(shank)]));
                    if getWaveforms
                        fname = fullfile(clusteringPath,[baseName '.spk.' num2str(shank)]);
                        f = fopen(fname,'r');
                        waveforms = LSB * double(fread(f,'int16'));
                        samples = size(waveforms,1)/size(time_stamps,1);
                        electrodes = size(xml.ElecGp{shank},2);
                        waveforms = reshape(waveforms, [electrodes,samples/electrodes,length(waveforms)/samples]);
                    end
                else
                    cluster_index = load(fullfile(clusteringPath, 'OriginalClus', [baseName '.clu.' num2str(shank)]));
                    time_stamps = load(fullfile(clusteringPath, 'OriginalClus', [baseName '.res.' num2str(shank)]));
                end
                cluster_index = cluster_index(2:end);
                nb_clusters = unique(cluster_index);
                nb_clusters2 = nb_clusters(nb_clusters > 1);
                for i = 1:length(nb_clusters2)
                    unit_nb = unit_nb +1;
                    spikes.ts{unit_nb} = time_stamps(cluster_index == nb_clusters2(i));
                    spikes.times{unit_nb} = spikes.ts{unit_nb}/xml.SampleRate;
                    spikes.shankID(unit_nb) = shank;
                    spikes.UID(unit_nb) = unit_nb;
                    spikes.cluID(unit_nb) = nb_clusters2(i);
                    spikes.cluster_index(unit_nb) = nb_clusters2(i);
                    spikes.total(unit_nb) = length(spikes.ts{unit_nb});
                    if getWaveforms & useNeurosuiteWaveforms
                        spikes.filtWaveform_all{unit_nb} = mean(waveforms(:,:,cluster_index == nb_clusters2(i)),3);
                        spikes.filtWaveform_all_std{unit_nb} = permute(std(permute(waveforms(:,:,cluster_index == nb_clusters2(i)),[3,1,2])),[2,3,1]);
                        [~,index1] = max(max(spikes.filtWaveform_all{unit_nb}') - min(spikes.filtWaveform_all{unit_nb}'));
                        spikes.maxWaveformCh(unit_nb) = xml.ElecGp{shank}(index1); % index 0;
                        spikes.maxWaveformCh1(unit_nb) = xml.ElecGp{shank}(index1)+1; % index 1;
                        spikes.filtWaveform{unit_nb} = spikes.filtWaveform_all{unit_nb}(index1,:);
                        spikes.filtWaveform_std{unit_nb} = spikes.filtWaveform_all_std{unit_nb}(index1,:);
                        spikes.peakVoltage(unit_nb) = max(spikes.filtWaveform{unit_nb}) - min(spikes.filtWaveform{unit_nb});
                    end
                end
                if getWaveforms
                    spikes.processinginfo.params.WaveformsSource = 'spk files';
                end
            end
            if getWaveforms & ~useNeurosuiteWaveforms
                spikes = GetWaveformsFromDat(spikes,xml,basepath,baseName,LSB,session);
            end
            clear cluster_index time_stamps
            
        % Loading phy    
        case 'phy'
            disp('loadSpikes: Loading Phy/Kilosort data')
            
            spike_cluster_index = readNPY(fullfile(clusteringPath, 'spike_clusters.npy'));
            spike_times = readNPY(fullfile(clusteringPath, 'spike_times.npy'));
            spike_amplitudes = readNPY(fullfile(clusteringPath, 'amplitudes.npy'));
            spike_clusters = unique(spike_cluster_index);
            filename1 = fullfile(clusteringPath,'cluster_group.tsv');
            filename2 = fullfile(clusteringPath,'cluster_groups.csv');
            if exist(fullfile(clusteringPath, 'cluster_ids.npy')) && exist(fullfile(clusteringPath, 'shanks.npy')) && exist(fullfile(clusteringPath, 'peak_channel.npy'))
                cluster_ids = readNPY(fullfile(clusteringPath, 'cluster_ids.npy'));
                unit_shanks = readNPY(fullfile(clusteringPath, 'shanks.npy'));
                peak_channel = readNPY(fullfile(clusteringPath, 'peak_channel.npy'))+1;
                if exist(fullfile(clusteringPath, 'rez.mat'))
                    load(fullfile(clusteringPath, 'rez.mat'))
                    temp = find(rez.connected);
                    peak_channel = temp(peak_channel);
                    clear rez temp
                end
            end
            
            if exist(filename1) == 2
                filename = filename1;
            elseif exist(filename2) == 2
                filename = filename2;
            else
                disp('Phy: No cluster group file found')
            end
            delimiter = '\t';
            startRow = 2;
            formatSpec = '%f%s%[^\n\r]';
            fileID = fopen(filename,'r');
            dataArray = textscan(fileID, formatSpec, 'Delimiter', delimiter, 'HeaderLines' ,startRow-1, 'ReturnOnError', false);
            fclose(fileID);
            j = 1;
            for i = 1:length(dataArray{1})
                if raw_clusters == 0
                    if strcmp(dataArray{2}{i},'good')
                        if sum(spike_cluster_index == dataArray{1}(i))>0
                            spikes.ids{j} = find(spike_cluster_index == dataArray{1}(i));
                            spikes.ts{j} = double(spike_times(spikes.ids{j}));
                            spikes.times{j} = spikes.ts{j}/xml.SampleRate;
                            spikes.cluID(j) = dataArray{1}(i);
                            spikes.UID(j) = j;
                            if exist('cluster_ids')
                                cluster_id = find(cluster_ids == spikes.cluID(j));
                                spikes.maxWaveformCh1(j) = double(peak_channel(cluster_id)); % index 1;
                                spikes.maxWaveformCh(j) = double(peak_channel(cluster_id))-1; % index 0;
                                
                                % Assigning shankID to the unit
                                for jj = 1:size(xml.AnatGrps,2)
                                    if any(xml.AnatGrps(jj).Channels == spikes.maxWaveformCh(j))
                                        spikes.shankID(j) = jj;
                                    end
                                end
                            end
                            spikes.total(j) = length(spikes.ts{j});
                            spikes.amplitudes{j} = double(spike_amplitudes(spikes.ids{j}));
                            j = j+1;
                        end
                    end
                else
                    spikes.ids{j} = find(spike_cluster_index == dataArray{1}(i));
                    spikes.ts{j} = double(spike_times(spikes.ids{j}));
                    spikes.times{j} = spikes.ts{j}/xml.SampleRate;
                    spikes.cluID(j) = dataArray{1}(i);
                    spikes.UID(j) = j;
                    spikes.amplitudes{j} = double(spike_amplitudes(spikes.ids{j}))';
                    j = j+1;
                end
            end
            
            if getWaveforms % gets waveforms from dat file
                spikes = GetWaveformsFromDat(spikes,xml,basepath,baseName,LSB,session);
            end
      
        % Loading klustaViewa - Kwik format (Klustasuite 0.3.0.beta4)
        case 'klustaViewa'
            disp('loadSpikes: Loading KlustaViewa data')
            shank_nb = 1;
            for shank = 1:shanks
                spike_times = double(hdf5read([folder, dataset, '.kwik'], ['/channel_groups/' num2str(shank-1) '/spikes/time_samples']));
                recording_nb = double(hdf5read([folder, dataset, '.kwik'], ['/channel_groups/' num2str(shank-1) '/spikes/recording']));
                cluster_index = double(hdf5read([folder, dataset, '.kwik'], ['/channel_groups/' num2str(shank-1) '/spikes/clusters/main']));
                waveforms = double(hdf5read([folder, dataset, '.kwx'], ['/channel_groups/' num2str(shank-1) '/waveforms_filtered']));
                clusters = unique(cluster_index);
                for i = 1:length(clusters(:))
                    cluster_type = double(hdf5read([folder, dataset, '.kwik'], ['/channel_groups/' num2str(shank-1) '/clusters/main/' num2str(clusters(i)),'/'],'cluster_group'));
                    if cluster_type == 2
                        indexes{shank_nb} = shank_nb*ones(sum(cluster_index == clusters(i)),1);
                        spikes.UID(shank_nb) = shank_nb;
                        spikes.ts{shank_nb} = spike_times(cluster_index == clusters(i))+recording_nb(cluster_index == clusters(i))*40*40000;
                        spikes.times{shank_nb} = spikes.ts{j}/xml.SampleRate;
                        spikes.total(shank_nb) = sum(cluster_index == clusters(i));
                        spikes.shankID(shank_nb) = shank-1;
                        spikes.cluID(shank_nb) = clusters(i);
                        spikes.filtWaveform_all{shank_nb} = mean(waveforms(:,:,cluster_index == clusters(i)),3);
                        spikes.filtWaveform_all_std{shank_nb} = permute(std(permute(waveforms(:,:,cluster_index == clusters(i)),[3,1,2])),[2,3,1]);
                        shank_nb = shank_nb+1;
                    end
                end
            end
            
            if getWaveforms % get waveforms
                spikes = GetWaveformsFromDat(spikes,xml,basepath,baseName,LSB,session);
            end
    end
    spikes.sessionName = baseName;
    
    % Generate spindices matrics
    spikes.numcells = length(spikes.UID);
    for cc = 1:spikes.numcells
        groups{cc}=spikes.UID(cc).*ones(size(spikes.times{cc}));
    end
    
    if spikes.numcells>0
        alltimes = cat(1,spikes.times{:}); groups = cat(1,groups{:});  % from cell to array
        [alltimes,sortidx] = sort(alltimes); groups = groups(sortidx); % sort both
        spikes.spindices = [alltimes groups];
    end
    
    % Attaching info about how the spikes structure was generated
    spikes.processinginfo.function = 'loadSpikes';
    spikes.processinginfo.version = 3.5;
    spikes.processinginfo.date = now;
    spikes.processinginfo.params.forceReload = forceReload;
    spikes.processinginfo.params.shanks = shanks;
    spikes.processinginfo.params.raw_clusters = raw_clusters;
    spikes.processinginfo.params.getWaveforms = getWaveforms;
    spikes.processinginfo.params.baseName = baseName;
    spikes.processinginfo.params.clusteringFormat = clusteringFormat;
    spikes.processinginfo.params.clusteringPath = clusteringPath;
    spikes.processinginfo.params.basepath = basepath;
    spikes.processinginfo.params.useNeurosuiteWaveforms = useNeurosuiteWaveforms;
    
    % Saving output to a buzcode compatible spikes file.
    if saveMat
        disp('loadSpikes: Saving spikes')
        save(fullfile(clusteringPath,[baseName,'.spikes.cellinfo.mat']),'spikes')
    end
end

end

function spikes = GetWaveformsFromDat(spikes,xml,basepath,baseName,LSB,session)
% Requires a neurosuite xml structure. 
% Bad channels must be deselected in the spike groups, or skipped beforehand
timerVal = tic;
nPull = 600; % number of spikes to pull out (default: 600)
wfWin_sec = 0.004; % Larger size of waveform windows for filterning. total width in ms
wfWinKeep = 0.0008; % half width in ms
filtFreq = [500,8000];
showWaveforms = true;

badChannels = [];

% Removing channels marked as Bad in session struct
if ~isempty(session)
    badChannels = session.channelTags.Bad.channels;
    if ~isempty(session.channelTags.Bad.spikeGroups)
        badChannels = [badChannels,session.extracellular.spikeGroups(session.channelTags.Bad.spikeGroups)+1];
    end
    badChannels = unique(badChannels);
end

% Removing channels that does not exist in SpkGrps
badChannels = [badChannels,setdiff([xml.AnatGrps.Channels],[xml.SpkGrps.Channels])+1];

% Removing channels with skip parameter from the xml
if isfield(xml.AnatGrps,'Skip')
    channelOrder = [xml.AnatGrps.Channels]+1;
    skip = find([xml.AnatGrps.Skip]);
    badChannels = [badChannels, channelOrder(skip)];
end
goodChannels = setdiff(1:xml.nChannels,badChannels);
nGoodChannels = length(goodChannels);

[b1, a1] = butter(3, filtFreq/xml.SampleRate*2, 'bandpass');

f = waitbar(0,['Getting waveforms from dat file'],'Name',['Processing ' baseName]);
if showWaveforms
    fig1 = figure('Name', ['Getting waveforms for ' baseName],'NumberTitle', 'off');
end
wfWin = round((wfWin_sec * xml.SampleRate)/2);
t1 = toc(timerVal);
s = dir(fullfile(basepath,[baseName '.dat']));
duration = s.bytes/(2*xml.nChannels*xml.SampleRate);
m = memmapfile(fullfile(basepath,[baseName '.dat']),'Format','int16','writable',false);
DATA = m.Data;

for ii = 1 : size(spikes.times,2)
    if ishandle(f)
        waitbar(ii/size(spikes.times,2),f,['Waveforms: ',num2str(ii),'/',num2str(size(spikes.times,2)),'. ', num2str(round(toc(timerVal)-t1)),' sec/unit, ', num2str(round(toc(timerVal)/60)) ' minutes total']);
    else
        disp('Canceling waveform extraction...')
        clear rawWaveform rawWaveform_std filtWaveform filtWaveform_std
        clear DATA
        clear m
        error('Waveform extraction canceled by user')
    end
    t1 = toc(timerVal);
    spkTmp = spikes.ts{ii}(find(spikes.times{ii} > wfWin_sec/1.8 & spikes.times{ii} < duration-wfWin_sec/1.8));
    
    if length(spkTmp) > nPull
        spkTmp = spkTmp(randperm(length(spkTmp)));
        spkTmp = sort(spkTmp(1:nPull));
    end
    
    % Determines the maximum waveform channel
    startIndicies = (spkTmp(1:min(100,length(spkTmp))) - wfWin)*xml.nChannels+1;
    stopIndicies =  (spkTmp(1:min(100,length(spkTmp))) + wfWin)*xml.nChannels;
    X = cumsum(accumarray(cumsum([1;stopIndicies(:)-startIndicies(:)+1]),[startIndicies(:);0]-[0;stopIndicies(:)]-1)+1);
    %     temp1 = reshape(double(m.Data(X(1:end-1))),xml.nChannels,(wfWin*2),[]);
    wf = LSB * mean(reshape(double(DATA(X(1:end-1))),xml.nChannels,(wfWin*2),[]),3);
    wfF2 = zeros((wfWin * 2),nGoodChannels);
    for jj = 1 : nGoodChannels
        wfF2(:,jj) = filtfilt(b1, a1, wf(goodChannels(jj),:));
    end
    [~, idx] = max(max(wfF2)-min(wfF2)); % max(abs(wfF(wfWin,:)));
    spikes.maxWaveformCh1(ii) = goodChannels(idx);
    spikes.maxWaveformCh(ii) = spikes.maxWaveformCh1(ii)-1;
    
    % Assigning shankID to the unit
    for jj = 1:size(xml.AnatGrps,2)
        if any(xml.AnatGrps(jj).Channels == spikes.maxWaveformCh(ii))
            spikes.shankID(ii) = jj;
        end
    end
    
    % Pulls the waveforms from the dat
    startIndicies = (spkTmp - wfWin+1);
    stopIndicies =  (spkTmp + wfWin);
    X = cumsum(accumarray(cumsum([1;stopIndicies(:)-startIndicies(:)+1]),[startIndicies(:);0]-[0;stopIndicies(:)]-1)+1);
    X = X(1:end-1) * xml.nChannels+spikes.maxWaveformCh1(ii);
    
    wf = LSB * double(reshape(DATA(X),wfWin*2,length(spkTmp)));
    wfF = zeros((wfWin * 2),length(spkTmp));
    for jj = 1 : length(spkTmp)
        wfF(:,jj) = filtfilt(b1, a1, wf(:,jj));
    end
    
    wf2 = mean(wf,2);
    rawWaveform = detrend(wf2 - mean(wf2))';
    rawWaveform_std = std((wf-mean(wf))');
    filtWaveform = mean(wfF,2)';
    filtWaveform_std = std(wfF');
    
    window_interval = wfWin-(wfWinKeep*xml.SampleRate):wfWin-1+(wfWinKeep*xml.SampleRate);
    spikes.rawWaveform{ii} = rawWaveform(window_interval); % keep only +- 0.8 ms of waveform
    spikes.rawWaveform_std{ii} = rawWaveform_std(window_interval);
    spikes.filtWaveform{ii} = filtWaveform(window_interval);
    spikes.filtWaveform_std{ii} = filtWaveform_std(window_interval);
    spikes.timeWaveform{ii} = (-wfWinKeep+1/xml.SampleRate:1/xml.SampleRate:wfWinKeep)*1000;
    spikes.peakVoltage(ii) = max(spikes.filtWaveform{ii})-min(spikes.filtWaveform{ii});
    
    if ishandle(fig1)
        figure(fig1)
        subplot(2,2,1), hold off
        plot(wfF2), hold on, plot(wfF2(:,idx),'k','linewidth',2), title('Filt waveform across channels'), xlabel('Samples'), hold off
        
        subplot(2,2,2), hold off,
        plot(wfF), title('Peak channel waveforms'), xlabel('Samples')
        
        subplot(2,2,3), hold on,
        plot(spikes.timeWaveform{ii},spikes.rawWaveform{ii}), title('Raw waveform'), xlabel('Time (ms)')
        xlim([-0.8,0.8])
        subplot(2,2,4), hold on,
        plot(spikes.timeWaveform{ii},spikes.filtWaveform{ii}), title('Filtered waveform'), xlabel('Time (ms)')
        xlim([-0.8,0.8])
    end
    clear wf wfF wf2 wfF2
end
if ishandle(f)
    spikes.processinginfo.params.WaveformsSource = 'dat file';
    spikes.processinginfo.params.WaveformsFiltFreq = filtFreq;
    spikes.processinginfo.params.Waveforms_nPull = nPull;
    spikes.processinginfo.params.WaveformsWin_sec = wfWin_sec;
    spikes.processinginfo.params.WaveformsWinKeep = wfWinKeep;
    spikes.processinginfo.params.WaveformsFilterType = 'butter';
    clear rawWaveform rawWaveform_std filtWaveform filtWaveform_std
    clear DATA
    clear m
    waitbar(ii/size(spikes.times,2),f,['Waveform extraction complete ',num2str(ii),'/',num2str(size(spikes.times,2)),'.  ', num2str(round(toc(timerVal)/60)) ' minutes total']);
    disp(['Waveform extraction complete. Total duration: ' num2str(round(toc(timerVal)/60)),' minutes'])
    if ishandle(fig1)
        set(fig1,'Name',['Waveform extraction complete for ' baseName])
    end
    % close(f)
end
end