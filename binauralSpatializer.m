classdef binauralSpatializer < audioPlugin
    % Binaural Spatialization Plugin Using HRTFs from SOFA files
    % Suhel Keswani, Georgia Institute of Technology, 2024.

    properties 
        azimuth = 0; % in degrees
        elevation = 0; % in degrees
        distance = 1; % plugin distance in m
        d0 = 1; % reference distance of input audio signal in m
        sofaFilePath = "SOFA/H10_48K_24bit_256tap_FIR_SOFA.sofa";
    end

    properties(Constant, Hidden)
        % Define plugin interface parameters
        PluginInterface = audioPluginInterface( ...
            audioPluginParameter('azimuth', 'Label', 'degrees', ...
                'Mapping', {'lin', -180, 180}), ...
            audioPluginParameter('elevation', 'Label', 'degrees', ...
                'Mapping', {'lin', -90, 90}), ...
            audioPluginParameter('distance', 'Label', 'meters', ...
                'Mapping', {'lin', 1, 10}) ...
            );
    end

    properties (Access = private)
        % For checking Azimuth and Elevation parameter updates
        lastAzimuth;                                                        
        lastElevation;

        % For SOFA file contents
        sofa;        

        % For left and right channel filters
        spatialFilterL;                                                     
        spatialFilterR;
        
        % For crossfading
        prevSpatialFilterL;
        prevSpatialFilterR;
        crossfadeCount = 0;
        crossfadeSamples = 50;  % Crossfade duration in samples
    end

    methods
        function reset(plugin)
            % On reset: load SOFA file, update last params, update filters
            if isempty(plugin.sofa)                                         
                plugin.sofa = sofaread(plugin.sofaFilePath);
            end

            %plugin.setSampleRate(plugin.sofa.SamplingRate);
            plugin.lastAzimuth = plugin.azimuth;
            plugin.lastElevation = plugin.elevation;
            plugin.updateSpatialFilters();
        end

        function updateSpatialFilters(plugin)
            % Interpolate HRTFs from SOFA file using parameters
            loc = [-plugin.azimuth, plugin.elevation]; % invert azimuth so negative degrees correspond to CCW roation
            interpolatedIR = squeeze(interpolateHRTF(plugin.sofa, loc)); % interpolate impulse response
            
            % Store current filters as previous filters for crossfade
            plugin.prevSpatialFilterL = plugin.spatialFilterL;
            plugin.prevSpatialFilterR = plugin.spatialFilterR;
            
            % Set new filters
            plugin.spatialFilterL = dsp.FIRFilter('Numerator', interpolatedIR(1, :));
            plugin.spatialFilterR = dsp.FIRFilter('Numerator', interpolatedIR(2, :));
            
            % Reset crossfade counter
            plugin.crossfadeCount = plugin.crossfadeSamples;
        end

        function out = process(plugin, in)
            % Make any stereo audio mono
            if size(in, 2) > 1                                              
                in = mean(in, 2, 'omitnan');
            end
        
            % Update filters for any change in parameters  
            if plugin.azimuth ~= plugin.lastAzimuth || plugin.elevation ~= plugin.lastElevation
                plugin.updateSpatialFilters();
                plugin.lastAzimuth = plugin.azimuth;
                plugin.lastElevation = plugin.elevation;
            end
        
            % Initialize output arrays
            outL = zeros(size(in));
            outR = zeros(size(in));
        
            % Apply crossfade if in progress
            if plugin.crossfadeCount > 0                
                % Crossfade between previous and current filters using Hann window
                alpha = 0.5 * (1 - cos(pi * (plugin.crossfadeSamples - plugin.crossfadeCount) / plugin.crossfadeSamples));
                outL = (1 - alpha) * plugin.prevSpatialFilterL(in) + alpha * plugin.spatialFilterL(in);
                outR = (1 - alpha) * plugin.prevSpatialFilterR(in) + alpha * plugin.spatialFilterR(in);
                
                % Decrement crossfade counter
                plugin.crossfadeCount = plugin.crossfadeCount - 1;
            else
                % No crossfade needed, use current filters
                outL = plugin.spatialFilterL(in);
                outR = plugin.spatialFilterR(in);
            end
        
            % Combine left and right channels into output
            out = [outL, outR];
        
            % Apply gain based on distance
            gain = (plugin.d0 / plugin.distance)^2;
            out = out * gain;
        
            % Normalize left and right channel
            maxVal = max(abs(out), [], 'all');
            if maxVal > 1
                out = out / maxVal;
            end
        end

    end
end