function [T] = processHydrophoneData(name,hydrophone_data,T_TPO_power_isppa,desired_isppa)

% PROCESS HYDROPHONE DATA post-process hydrophone data from FUS initiative (2024) 
%
% DESCRIPTION:
%     processHydrophoneData takes the raw hydrophone data measured by the
%     FUS initiative at Radboud University (2024)and post-processes it. The
%     measured intensity field is re-scaled to W/cm^2. Then using the power
%     setting on the TPO during the measurement, and the power setting on
%     the TPO to reach the desired Isppa (higher), the measured intensity
%     is rescaled again, which optimally will yield the desired Isppa. The
%     axial distance between the exit plane of the transducer and the
%     beginning of the measured axial distances is padded with NaN values.
%     The maximum and sum intensity per axial slice is calculated, and a
%     struct is returned. 
%
% USAGE:
%     T = processHydrophoneData(name,hydrophone_data,T_TPO_power_isppa,desired_isppa)
%
% EXAMPLES:
%     T = processHydrophoneData('CTX250-014',CTX25014,power_isppa_CTX25014,desired_isppa); 
%
% INPUTS
%     name              - Transducer/measurement name
%     hydrophone_data   - Raw hydrophone data provided by FUS Initiative
%     T_TPO_power_isppa - A conversion table with the columns 'globalPower'
%                         and 'intensity', that shows for the specific 
%                         transducer-TPO combination which globalPower is
%                         registered to which Isppa on the user interface. 
%     desired_isppa     - The intended Isppa set on the TPO for the
%                         experiment
%
% OUTPUTS:
%     T                 - A struct containing the processed hydrophone data

    % Find the transducer-specific TPO power setting required to reach the desired Isppa 
    T_TPO_power = T_TPO_power_isppa.globalPower(min(find(abs(T_TPO_power_isppa.intensity - desired_isppa)==min(abs(T_TPO_power_isppa.intensity - desired_isppa)))));
    
    % Set the transducer name 
    T.name = name;
    fprintf(['\n' 'Processing ' T.name '... \n']);
   
    % Extract relevant data from the hydrophone raw data struct 
    T.drive_power = hydrophone_data.data{1,1}.driverAmp.power;              % Power used during measurement 
    T.isppa_raw = hydrophone_data.data{1,1}.measurement.ISPPA.data;         % Raw Isppa measured with hydrophone
    T.coord_x = hydrophone_data.data{1,1}.measurement.cor.x;                % x-coordinate relative to transducer center of exit plane [mm]
    T.coord_y = hydrophone_data.data{1,1}.measurement.cor.y;                % y-coordinate relative to transducer center of exit plane [mm]
    T.coord_z = hydrophone_data.data{1,1}.measurement.cor.z;                % z-coordinate relative to transducer center of exit plane [mm]
    
    % Perform calculations
    T.isppa_cm = T.isppa_raw/10000;                                         % Re-scale Isppa to W/cm^2
    T.tpo_power = T_TPO_power;                                              % Store the required TPO power to reach desired Isppa in the struct
    T.scale_factor = T.tpo_power/T.drive_power;                             % Calculate the scaling factor 
    T.isppa = T.isppa_cm*T.scale_factor;                                    % Scale the Isppa appropriately 
    T.z_min = nanmin(T.coord_z(:));                                         % Store the minimum measurement coordinate along the axial z-axis [mm]

    % Derive step size from raw hydrophone data 
    step_size = abs(T.coord_x(1,10,1)-T.coord_x(1,9,1));
    if sum([abs(T.coord_x(1,10,1)-T.coord_x(1,9,1)) ...
            abs(T.coord_y(10,1,1)-T.coord_y(9,1,1)) ...
            abs(T.coord_z(1,1,10)-T.coord_z(1,1,9))] == step_size) == 3
        disp(['Dimension step sizes correspond at ' num2str(step_size) ' mm']); 
    else 
        error('The step size is not equal across dimensions'); 
    end 

    % Crop CTX500-06 for grid correspondence with CTX250-014
    if strcmp(T.name,'CTX500-006')
        T.isppa = T.isppa(3:end,:,:); 
        T.coord_x = T.coord_x(3:end,:,:);
        T.coord_y = T.coord_y(3:end,:,:);
        T.coord_z = T.coord_z(3:end,:,:);
    end 
    
    % Store step size 
    T.step_size = step_size; 
    
    % Determine number of grid points required to start axial distance at 0
    T.z_offset_gridpoints = T.z_min/T.step_size; 
    
    % Generate temporary matrix with NaN to add padding for 0-z_min range
    T.size = size(T.isppa); 
    temp_matrix = nan(T.size(1),T.size(2),T.size(3)+T.z_offset_gridpoints); 
    
    % Fill matrix with measured data points 
    temp_isppa = temp_matrix; temp_isppa(:,:,T.z_offset_gridpoints+1:end) = T.isppa; 
    temp_coord_x = temp_matrix; temp_coord_x(:,:,T.z_offset_gridpoints+1:end) = T.coord_x; 
    temp_coord_y = temp_matrix; temp_coord_y(:,:,T.z_offset_gridpoints+1:end) = T.coord_y; 
    temp_coord_z = temp_matrix; temp_coord_z(:,:,T.z_offset_gridpoints+1:end) = T.coord_z; 
    
    % Reduce to coordinates to relevant dimension only
    temp_coord_x = squeeze(temp_coord_x(20,:,20)); 
    temp_coord_y = squeeze(temp_coord_y(:,20,20)); 
    temp_coord_z = squeeze(temp_coord_z(20,20,:)); 
    T.isppa = temp_isppa; 
    T.coord_x = temp_coord_x; 
    T.coord_y = temp_coord_y; 
    T.coord_z = temp_coord_z; 
    
    % Calculate maximum per slice along axial plane 
    T.axial_max = squeeze(nanmax(T.isppa,[],[1 2])); 
    
    % Calculate sum per slice (total) along axial plane 
    T.axial_sum = squeeze(sum(sum(T.isppa,1,'omitnan'),2,'omitnan'));
    
    % For CTX250-026: cut grid so the near-field is isolated for the
    % focal nearfield volume calculations
    if strcmp(name, 'nearfield_CTX250-026')
        T.isppa_orig = T.isppa;
        T.coord_z_orig = T.coord_z;
        T.isppa = T.isppa(:,:,1:60);
        T.coord_z = T.coord_z(1:60);
    end 
    
    % Determine the location of the Isppa 
    [dim1, dim2, dim3] = size(T.isppa); 
    [Isppa_value, lin_idx] = nanmax(T.isppa(:)); 
    [max.x, max.y, max.z] = ind2sub(size(T.isppa),lin_idx); 
    T.max_x = max.x; 
    T.max_y = max.y; 
    T.max_z = max.z; 
    fprintf('Value of free-water Isppa (W/cm^2): %d \n', Isppa_value);

    % Get coordinate position of Isppa in mm
    Isppa_mm = [T.coord_x(max.x), T.coord_y(max.y), T.coord_z(max.z)];
    fprintf('Position of free-water Isppa (mm): x = %.4f, y = %.4f, z = %.4f\n', Isppa_mm(1), Isppa_mm(2), Isppa_mm(3));
    
    % Get focal dimension characteristics =====================================
    % Threshold image at 0.5I for -3dB threshold and 0.25I for -6dB
    Isppa_3dB = zeros(size(T.isppa)); 
    Isppa_3dB(T.isppa>0.5*Isppa_value) = 1; 
    T.dB3_Isppa_mask = Isppa_3dB; 
    Isppa_6dB = zeros(size(T.isppa)); 
    Isppa_6dB(T.isppa>0.25*Isppa_value) = 1; 
    T.dB6_Isppa_mask = Isppa_6dB; 

    % Process 3dB
    % Get shape and position of focal region(s) 
    labeled_regions = bwlabeln(Isppa_3dB); % ensures that both near-field and focus are captured 
    stats_3dB = regionprops3(labeled_regions, T.isppa, 'Centroid', 'Volume', 'PrincipalAxisLength'); % get info on centroid(s) 

    % Get focal volume in mm^3 
    volume_3dB = stats_3dB.Volume; 
    volume_3dB_mm = volume_3dB * T.step_size^3; 
    for i = 1:length(volume_3dB_mm)
        fprintf('-3dB: Focal volume, volume %d (mm^3) = %.2f\n', i, volume_3dB_mm(i));
    end

    % Get focal dimensions 
    focal_dim_3dB = [stats_3dB.PrincipalAxisLength(:,2), stats_3dB.PrincipalAxisLength(:,3), ...
            stats_3dB.PrincipalAxisLength(:,1)];
    focal_dim_3dB_mm = focal_dim_3dB*T.step_size;
    for i = 1:size(focal_dim_3dB_mm, 1)
        fprintf('-3dB: Focal dimensions, volume %d (mm): x = %.1f, y = %.1f, z = %.1f\n', ...
                i, focal_dim_3dB_mm(i, 1), focal_dim_3dB_mm(i, 2), focal_dim_3dB_mm(i, 3));
    end

    % Get centroid coordinates 
    centroid_xyz_3dB = stats_3dB.Centroid;
    centroid_xyz_mm_3dB = [T.coord_x(round(centroid_xyz_3dB(:,1)))', T.coord_y(round(centroid_xyz_3dB(:,2))), T.coord_z(round(centroid_xyz_3dB(:,3)))];
    for i = 1:size(centroid_xyz_mm_3dB, 1)
        fprintf('-3dB: Centroid coordinates, volume %d (mm): x = %.1f, y = %.1f, z = %.1f\n', ...
                i, centroid_xyz_mm_3dB(i, 1), centroid_xyz_mm_3dB(i, 2), centroid_xyz_mm_3dB(i, 3));
    end

    % Process 6dB
    % Get shape and position of focal region(s) 
    labeled_regions = bwlabeln(Isppa_6dB); % ensures that both near-field and focus are captured 
    stats_6dB = regionprops3(labeled_regions, T.isppa, 'Centroid', 'Volume', 'PrincipalAxisLength'); % get info on centroid(s) 

    % Get focal volume in mm^3 
    volume_6dB = stats_6dB.Volume; 
    volume_6dB_mm = volume_6dB * T.step_size^3; 
    for i = 1:length(volume_6dB_mm)
        fprintf('-6dB: Focal volume, volume %d (mm^3) = %.2f\n', i, volume_6dB_mm(i));
    end

    % Get focal dimensions 
    focal_dim_6dB = [stats_6dB.PrincipalAxisLength(:,2), stats_6dB.PrincipalAxisLength(:,3), ...
            stats_6dB.PrincipalAxisLength(:,1)];
    focal_dim_6dB_mm = focal_dim_6dB*T.step_size;
    for i = 1:size(focal_dim_6dB_mm, 1)
        fprintf('-6dB: Focal dimensions -6dB, volume %d (mm): x = %.1f, y = %.1f, z = %.1f\n', ...
                i, focal_dim_6dB_mm(i, 1), focal_dim_6dB_mm(i, 2), focal_dim_6dB_mm(i, 3));
    end

    % Get centroid coordinates 
    centroid_xyz_6dB = stats_6dB.Centroid;
    centroid_xyz_mm_6dB = [T.coord_x(round(centroid_xyz_6dB(:,1)))', T.coord_y(round(centroid_xyz_6dB(:,2))), T.coord_z(round(centroid_xyz_6dB(:,3)))];
    for i = 1:size(centroid_xyz_mm_6dB, 1)
        fprintf('-6dB: Centroid coordinates -6dB, volume %d (mm): x = %.1f, y = %.1f, z = %.1f\n', ...
                i, centroid_xyz_mm_6dB(i, 1), centroid_xyz_mm_6dB(i, 2), centroid_xyz_mm_6dB(i, 3));
    end

    % Compile focal dimension table and write to disc 
    focal_metrics = table();
    focal_metrics.dB_Level = [repmat("-3dB", length(volume_3dB_mm), 1); repmat("-6dB", length(volume_6dB_mm), 1)];
    volume_numbers_3dB = (1:length(volume_3dB_mm))';
    volume_numbers_6dB = (1:length(volume_6dB_mm))';
    focal_metrics.VolumeNumber = [volume_numbers_3dB; volume_numbers_6dB];
    focal_metrics.Volume_mm3 = [volume_3dB_mm; volume_6dB_mm];
    focal_metrics.Dimensions_mm_x = [focal_dim_3dB_mm(:, 1); focal_dim_6dB_mm(:, 1)];
    focal_metrics.Dimensions_mm_y = [focal_dim_3dB_mm(:, 2); focal_dim_6dB_mm(:, 2)];
    focal_metrics.Dimensions_mm_z = [focal_dim_3dB_mm(:, 3); focal_dim_6dB_mm(:, 3)];
    focal_metrics.Centroid_mm_x = [centroid_xyz_mm_3dB(:, 1); centroid_xyz_mm_6dB(:, 1)];
    focal_metrics.Centroid_mm_y = [centroid_xyz_mm_3dB(:, 2); centroid_xyz_mm_6dB(:, 2)];
    focal_metrics.Centroid_mm_z = [centroid_xyz_mm_3dB(:, 3); centroid_xyz_mm_6dB(:, 3)];
    disp(focal_metrics)
    writetable(focal_metrics, ['focal_metrics_' name '.xlsx']);
end
