function subsetPlots = firingRateMaps2D(cell_metrics,UI,ii,col)
    % This is a example template for creating your own custom single cell plots
    %
    % INPUTS
    % cell_metrics      cell_metrics struct
    % UI                the struct with figure handles, settings and parameters
    % ii                index of the current cell
    % col               color of the current cell
    %
    % OUTPUT
    % subsetPlots       a struct with any extra single cell plots from synaptic partner cells
    %   .xaxis          x axis data (Nx1), where N is the number of samples 
    %   .yaxis          y axis data (NxM), where M is the number of cells
    %   .subset         list of cellIDs (Mx1)
    
    % By Peter Petersen
    % petersen.peter@gmail.com
    % Last updated 15-12-2019
    
    subsetPlots = [];
    
% %     plot(cell_metrics.waveforms.time{ii},cell_metrics.waveforms.filt_zscored(:,ii),'-','Color',col)
% Spikes over trajectory could also be implemented easily. Should store the
% trajectory (X/Y/T) in 'general' and the timestamps of up to N random
% spikes with the cells to pick from or alternatively load them from file.

if UI.BatchMode && isfield(cell_metrics.general.batch{cell_metrics.batchIDs(ii)},...
        'firingRateMaps')
    x_bins = cell_metrics.general.batch{cell_metrics.batchIDs(ii)}...
        .firingRateMaps.radialMazeMaps.x_bins;
    y_bins = cell_metrics.general.batch{cell_metrics.batchIDs(ii)}...
        .firingRateMaps.radialMazeMaps.y_bins;
    detectorinfo = cell_metrics.general.batch{cell_metrics.batchIDs(ii)}...
        .firingRateMaps.radialMazeMaps.detectorinfo;
    
elseif isfield(cell_metrics.general,'firingRateMaps')
    x_bins = cell_metrics.general.firingRateMaps.radialMazeMaps.x_bins;
    y_bins = cell_metrics.general.firingRateMaps.radialMazeMaps.y_bins;
    detectorinfo = cell_metrics.general.firingRateMaps.radialMazeMaps.detectorinfo;
else
    title('Radial Maze rate maps')
    text(0.5,0.5,'Not data','FontWeight','bold','HorizontalAlignment','center')
    return
end    
    
subplot(1,2,1)
scatter(x_bins,y_bins,[],cell_metrics.firingRateMaps.radialMazeMaps{ii}(:,1),'s','filled');
xlim([0 max(x_bins)]);
xlabel('Position (cm)');
ylim([0 max(y_bins)]);
ylabel('Position (cm)');
rew_arms1 = detectorinfo.rewarded_arms(1,~isnan(detectorinfo.rewarded_arms(1,:)));
title(strcat('Rewarded Arms: ',detectorinfo.arm_labels{rew_arms1}));

if size(cell_metrics.firingRateMaps.radialMazeMaps{ii},2)>1
    subplot(1,2,2)
    scatter(x_bins,y_bins,[],cell_metrics.firingRateMaps.radialMazeMaps{ii}(:,2),'s','filled');
    xlim([0 max(x_bins)]);
    xlabel('Position (cm)');
    ylim([0 max(y_bins)]);
    ylabel('Position (cm)');
    rew_arms2 = detectorinfo.rewarded_arms(2,~isnan(detectorinfo.rewarded_arms(2,:)));
    title(strcat('Rewarded Arms: ',detectorinfo.arm_labels{rew_arms2}));
    % TODO: Plot the arms! .05 .5 .95 * max(x_bins)
    % alpha(gca,.2); Multiple colormaps - check plots for Huganir paper
end
end