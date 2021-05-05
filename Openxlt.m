%--------------------------------------------------------------------------
%
%   Openxlt
%
%--------------------------------------------------------------------------
%
%   Intro
%
%       Load XLTEK .eeg data.
%
%   Usage
%
%       o = Openxlt('test/raw_data');
%       o = o.load();
%
%   Author
%
%       Jiarui Wang :: jwang04@g.harvard.edu
%
%--------------------------------------------------------------------------
classdef Openxlt
    properties
        % filenames
        name_script;
        name_dir;
        name_file_root;
        name_file_eeg;
        name_file_stc;
        name_file_ent;
        name_file_vtc;
        
        % numbers
        %n_data_files;
        
        % load states
        state_loaded_eeg = false;
        state_loaded_eeg_montages = false;
        state_loaded_eeg_admin = false;
        state_loaded_eeg_name = false;
        state_loaded_eeg_personal = false;
        state_loaded_stc = false;
        state_loaded_ent = false;
        state_loaded_vtc = false;
        state_loaded_etc = [];
        
        % structs
        object_eeg; % main file
        object_eeg_list; % main file, additional properties
        object_eeg_montage; % list of electrode labels
        object_stc; % list of etc and erd data files
        object_ent; % list of annotations
        object_vtc; % list of video files
        object_etc; % list of erd data file pointers
        
        % information
        subject_id;
        subject_firstname;
        subject_middlename;
        subject_lastname;
        subject_guid;
        subject_agelabel;
        subject_age;
        subject_birthdatelabel;
        subject_birthdatestr;
        subject_birthdate;
        subject_genderlabel;
        subject_gender;
        subject_handedness;
        subject_height;
        subject_weight;
        subject_frequency_sampling;
        subject_headbox_sn;
        subject_study_creation_time;
        subject_study_xl_creation_time;
        subject_study_modification_time;
        subject_study_epoch_length;
        subject_study_writer_version_major;
        subject_study_writer_version_minor;
        subject_study_product_version_high;
        subject_study_product_version_low;
        subject_study_original_study_guid;
        subject_study_guid;
        subject_study_file_contents;
        
        % recording information
        %time_recording_start;
        %time_recording_end;
        %ent_cleaned;
    end
    
    methods (Hidden)
        %------------------------------------------------------------------
        %                                                               
        %   _|_|      _|_|_|    _|_|_|  _|_|_|  _|_|_|  
        % _|    _|  _|        _|          _|      _|    
        % _|_|_|_|    _|_|    _|          _|      _|    
        % _|    _|        _|  _|          _|      _|    
        % _|    _|  _|_|_|      _|_|_|  _|_|_|  _|_|_|  
        %    
        %
        % ASCII parser
        %
        function [obj_struct,obj_cursor] = parse_obj(self, cursor,intxt)
            state_pass = true;
            state_type = 0;
            while (state_pass)
                if (cursor > length(intxt))
                    % stop parsing at end of file
                    %disp(intxt((cursor-20):(cursor-1)));
                    break;
                end
                if (intxt(cursor) == '(')
                    [ostruct,cursor] = self.parse_obj(cursor+1,intxt);
                    state_type = 'o';
                elseif (intxt(cursor) == '.')
                    if (intxt(cursor+1) == '"')
                        [ostruct,cursor] = self.parse_pair(cursor+1,intxt);
                        state_type = 'p';
                    elseif (intxt(cursor+1) == '(')
                        [ostruct,cursor] = self.parse_array(cursor+1,intxt);
                        state_type = 'a';
                    end
                elseif (intxt(cursor) == ')')
                    break;
                elseif (intxt(cursor) == '"')
                    [ostruct,cursor] = self.parse_array(cursor,intxt);
                    state_type = 'v';
                end
                cursor = cursor + 1;
            end

            % output
            switch (state_type)
                case ('o')
                    obj_struct = ostruct;
                case ('p')
                    obj_struct = struct(ostruct.key,ostruct.val);
                case ('a')
                    obj_struct = ostruct.array;
                case ('v')
                    obj_struct = ostruct.array;
                otherwise
                    obj_struct = struct();
            end
            obj_cursor = cursor;
        end

        % pair
        function [obj_struct,obj_cursor] = parse_pair(self, cursor,intxt)
            state_pass = true;
            state_iskey = false;
            %state_isval = false;
            while (state_pass)
                %if ((intxt(cursor) == '"') && (~state_isval))
                if (intxt(cursor) == '"')
                    if (~state_iskey)
                        % start key
                        state_iskey = true;
                        key = []; %intxt(cursor);
                    else
                        % end key
                        state_iskey = false;
                        if (intxt(cursor+1) == ')')
                            val = [];
                            break
                        end
                    end
                elseif (intxt(cursor) == ',')
                    %state_isval = true;
                    % add 2 for space after comma
                    [obj_struct,cursor] = self.parse_value(cursor+2,intxt);
                    val = obj_struct;
                    break;
                elseif (state_iskey)
                    key = [key,intxt(cursor)];
                end
                cursor = cursor + 1;
            end

            obj_struct = struct();
            obj_struct.key = self.clean_key(key);
            obj_struct.val = val;
            obj_cursor = cursor;
        end

        % array
        function [obj_struct,obj_cursor] = parse_array(self, cursor,intxt)
            state_pass = true;
            out_array = {};
            while (state_pass)
                if (intxt(cursor) == '(')
                    [ostruct,cursor] = self.parse_obj(cursor+1,intxt);
                    out_array = [out_array {ostruct}];
                    try
                        if (intxt(cursor+1) ~= ',')
                            break
                        end
                    catch
                        break
                    end
                elseif (intxt(cursor) == '"')
                    [ostruct,cursor] = self.parse_value(cursor,intxt);
                    out_array = [out_array {ostruct}];
                    try
                        if (intxt(cursor+1) ~= ',')
                            break
                        end
                    catch
                        break
                    end
                end
                cursor = cursor + 1;
            end
            obj_struct.array = out_array;
            obj_cursor = cursor;
        end

        % value
        function [obj_struct,obj_cursor] = parse_value(self, cursor,intxt)
            state_pass = true;
            state_isobj = false;
            val = '0000000000000000000000000000000000000000000000000000000000000000';
            val_idx = 1;
            state_paren = false;
            while (state_pass)
                if (intxt(cursor) == '(')
                    [val,cursor] = self.parse_obj(cursor+1,intxt);
                    state_isobj = true;
                    break
                elseif (intxt(cursor) == ')')
                    cursor = cursor - 1;
                    break;
                elseif ((intxt(cursor) == ',') && (~state_paren))
                    cursor = cursor - 1;
                    break;
                else
                    if (intxt(cursor) == '"')
                        state_paren = ~state_paren;
                    end
                    val(val_idx) = intxt(cursor);
                    val_idx = val_idx + 1;
                end
                cursor = cursor + 1;
            end
            %if (ischar(val))
            if (state_isobj)
                obj_struct = val;
            else
                obj_struct = val(1:(val_idx-1));
            end
            obj_cursor = cursor;
        end

        % modify key strings to serve as variable names
        function [cleaned_key] = clean_key(self, key)
            % clean key
            %key(key == '@') = [];
            key = replace(key,' ','');
            %key = replace(key,'!','_');
            key = replace(key,'@','');
            key = replace(key,'#','');
            %key = replace(key,'$','_');
            %key = replace(key,'%','_');
            %key = replace(key,'^','_');
            %key = replace(key,'&','_');
            %key = replace(key,'*','_');
            %key = replace(key,'-','_');
            %key = replace(key,'+','_');
            %key = replace(key,'=','_');
            %key = replace(key,'[','_');
            %key = replace(key,']','_');
            %key = replace(key,'{','_');
            %key = replace(key,'}','_');
            %key = replace(key,'|','_');
            %key = replace(key,':','_');
            %key = replace(key,';','_');
            %key = replace(key,'"','_');
            key = replace(key,'''','');
            %key = replace(key,'/','_');
            %key = replace(key,'\','_');
            %key = replace(key,'?','_');
            %key = replace(key,'`','_');
            %key = replace(key,'~','_');
            %key = replace(key,'>','_');
            %key = replace(key,'<','_');
            
            % pad variable names with leading zeros
            if (isstrprop(key(1),'digit'))
                key = ['num',key];
            end

            % check if valid
            if (~isvarname(key))
                fprintf(2,'[!] Parse ASCII warning, invalid variable name: %s\n',key);
                key = 'UNKNOWN';
            end

            cleaned_key = key;
        end
        
        % parse ascii text into list of objects
        function [outtxt] = clean_txt(self, intxt)
            level = 0;
            state_started = false;
            cursor_start = 1;
            outcell = {};
            for cursor = 1:length(intxt)
                current = intxt(cursor);
                if (current == '(')
                    if (level == 0)
                        state_started = true;
                        cursor_start = (cursor);
                    end
                    level = level + 1;
                elseif (current == ')')
                    level = level - 1;
                    if ((level == 0) && state_started)
                        state_started = false;
                        outcell = [outcell, {intxt(cursor_start:cursor)}];
                        %break
                    end
                end
            end
            %outtxt = intxt(1:(cursor));
            outtxt = outcell;
        end
        %
        % End ASCII parser
        %
        %------------------------------------------------------------------
        
        %
        % carveF - search director for files containing suffix
        %
        function outL = carveF(self, indir, suffix)
            d = dir(indir);
            disdir = [d.isdir];
            dname = {d.name};
            L = dname(~ disdir);
            outL = {};
            j = 1;
            for i = 1:length(L)
                if (endsWith(upper(L{i}),upper(suffix)))
                    outL{j} = sprintf('%s/%s',indir,L{i});
                    j = j + 1;
                end
            end
        end
        
        %
        % checkFileExists - check for the existence of a file by suffix
        %
        function name_file_out = checkFile(self, suffix)
            name_file_out = sprintf('%s/%s%s',self.name_dir,self.name_file_root,suffix);
            %name_file_out = replace(name_file_out,' ','\ ');
            fprintf('[*] Found %s file in: %s\n',suffix,name_file_out);
            if (~exist(name_file_out,'file'))
                fprintf(2,'[!] Warning in %s, file not found: %s\n',self.name_script,name_file_out);
            end
        end
        
        %
        % parseAsciiPrint - copypaste of parseAscii, but print to stdout
        %
        function [] = parseAsciiPrint(self, intxt)
            %outStr = '';
            
            level = 0;
            state_quote = false;
            prev = '';
            for i = 1:length(intxt)
                current = intxt(i);
                
                if (strcmp(current,'"'))
                    fprintf('%s',current);
                    state_quote = ~ state_quote;
                elseif (state_quote)
                   % quote bypass
                   fprintf('%s',current);
                elseif (strcmp(current,'('))
                    fprintf('\n');
                    
                    % indent
                    for j = 1:level
                        fprintf('  ');
                    end
                    level = level + 1;
                    fprintf('%s','(');
                    
                    % courtesy new line
                    fprintf('\n');
                    for j = 1:level
                        fprintf('  ');
                    end
                    
                elseif (strcmp(current,')'))
                    fprintf('\n');
                    
                    level = level - 1;
                    for j = 1:level
                        fprintf('  ');
                    end
                    fprintf('%s',')');
                    if (level == 0)
                        fprintf('\n');
                        break
                    end
                elseif (strcmp(current,','))
                    if (strcmp(prev,'"'))
                        %fprintf(':');
                        fprintf(',');
                    else
                        fprintf(',');
                    end
                elseif (strcmp(current,'.'))
                    fprintf('.')
                else
                    fprintf('%s',current);
                end
                
                prev = current;
            end
        end
        
        %
        % parse montage binary string from .eeg file
        %
        function [self] = parseMontageFromEEG(self)
            if ((~self.state_loaded_eeg_montages) || (isempty(self.object_eeg_montage)))
                fprintf(2,'[!] skipped parseMontageFromEEG: Montage binary was not successfully loaded from EEG\n')
                return
            end
            
            mtxt = strsplit(self.object_eeg_montage.montage,'0x');
            mtxt = lower(mtxt{end});
            
            % parse
            hex_ChanNames = '4368616e4e616d6573';
            % find ChanNames
            for i = 1:length(mtxt)
                if (strcmp(hex_ChanNames,mtxt(i:(i+length(hex_ChanNames)-1)))) %(mod(i,2) == 0)
                    idx_start = i + length(hex_ChanNames);
                    %fprintf('%i\n',idx_start)
                    break
                end
            end
            cursor = idx_start;
            cursor = cursor + 4; % skip 2 bytes "0004"
            cursor = cursor + 4; % skip 2 bytes, number of bytes of total channel names data chunk
            cursor = cursor + 4; % skip 2 bytes "0000"
            
            % read number of channels
            width = 4;
            
            n_chan = swapbytes(uint16(hex2dec(mtxt(cursor:(cursor + width - 1)))));
            self.object_eeg_montage.chan_number = n_chan;
            cursor = cursor + width;
            
            % skip bytes
            % these bytes should be constant across subjects
            cursor = cursor + 6;
            
            % read channel labels
            chan_labels = cell(1,n_chan);
            for i = 1:n_chan
                % read width
                width = 2 * double(hex2dec(mtxt(cursor:(cursor+1))));
                cname = mtxt((cursor+2):(cursor+width-1));
                
                % parse label string
                lstring = '';
                for j = 1:length(cname)
                    if (mod(j,2) == 0)
                        char_c = cname((j-1):j);
                        if (~strcmp(char_c,'00'))
                            lstring = [lstring,char(hex2dec(char_c))];
                        end
                    end
                end
                chan_labels{i} = lstring;
%                 fprintf('%i %i %s %s_%s_%s\n',width,length(cname),cname,...
%                     mtxt((cursor-7):cursor), mtxt(cursor), mtxt(cursor:(cursor+7)) );
                cursor = cursor + width;
            end
            self.object_eeg_montage.chan_labels = chan_labels;
        end
        
%                                       
% _|_|_|_|  _|_|_|_|    _|_|_|  
% _|        _|        _|        
% _|_|_|    _|_|_|    _|  _|_|  
% _|        _|        _|    _|  
% _|_|_|_|  _|_|_|_|    _|_|_|  
%                               
        
        %
        % Load EEG binary
        %
        function self = loadEEG(self)
            fprintf('\tLoading EEG: %s ..\n',self.name_file_eeg);
            BYTES_INT32 = 4; % number of bytes for int32
            BYTES_ID = 20; % number of bytes for magic number for file format identification
            BYTES_LOG = 320; % number of bytes for logs
            
            % magic number for identifying .eeg format
            ID_EEG = [-905246832;298899349;-1610599761;-1521198300;65539];
            
            % check format
            f_eeg = fopen(self.name_file_eeg,'r');
            eeg_id = fread(f_eeg,[BYTES_ID/BYTES_INT32,1],'int32');
            if (~all(eeg_id == ID_EEG))
                fprintf(2,'[!] Warning in %s.loadEEG: file %s does not match filetype identifier\n',self.name_script,self.name_file_eeg);
            end
            
            % read binary
            
            % creation time
            eeg_creation_time = fread(f_eeg,[1,1],'int32');
            %fprintf('\tEEG Creation Time: %i\n',eeg_creation_time);
            
            % 8 bytes of zeros
            null = fread(f_eeg,[1,1],'int32');
            null = fread(f_eeg,[1,1],'int32');
            
            % log
            eeg_log = char(fread(f_eeg,[BYTES_LOG,1],'int8'));
            %eeg_log = fread(f_eeg,[BYTES_LOG,1],'*char');
            %fprintf('\tEEG Log:\n');
            %fprintf('%s\n',(eeg_log'));
            
            % unknown
            %   the first three bytes are always all -1
            %   the middle 3 bytes are unique to each file
            %   the last byte is always a 0
            null = fread(f_eeg,[7,1],'int8');
            %fprintf('[!] 7B: %s\n',char(null));
            %disp(null)
            
            % read ascii
            %fprintf('\tRead ascii ..\n');
            eeg = char(fread(f_eeg,'int8'))'; 
            %eeg = (fread(f_eeg,'*char'))';
            
            % close file
            fclose(f_eeg);
            %fprintf('\tFinished reading.\n');
            
            % parse ascii
            %[oeeg,~] = self.parse_obj(1,eeg(2:end));
            %[outtxt] = clean_txt(self, intxt);
            [eeg_cleaned] = self.clean_txt(eeg);
            
            oeeg_list = {};
            for i = 1:length(eeg_cleaned)
                [oeeg,~] = self.parse_obj(1,eeg_cleaned{i});
                oeeg_list = [oeeg_list, {oeeg}];
            end
            %printstruct(oeeg)
            self.object_eeg = oeeg_list{1}; % oeeg
            self.object_eeg_list = oeeg_list;
            
            %
            % Read Montages
            %
            % get Montages index
            for i_mont = 1:length(self.object_eeg)
                try
                    self.object_eeg{i_mont}(1).Montages;
                    break
                end
            end
            object_mont = self.object_eeg{i_mont};
            % Montages:Data
            for i_data = 1:length(object_mont)
                try
                    object_mont(i_data).Montages(1).Data;
                    break
                end
            end
            
            try
                %fprintf('[!] NUMBER OF MONTAGES: %i\n',length(object_mont(i_data).Montages));
                o_data = struct();
                o_data.creation_time = str2double(object_mont(i_data).Montages(1).Data.CreationTime);
                o_data.file_name = object_mont(i_data).Montages(2).Data.FileName;
                o_data.modification_time = str2double(object_mont(i_data).Montages(3).Data.ModificationTime);
                o_data.montage = object_mont(i_data).Montages(4).Data.Montage;
                o_data.name = object_mont(i_data).Montages(5).Data.Name;
                o_data.type = object_mont(i_data).Montages(6).Data.Type;
                o_data.user = object_mont(i_data).Montages(7).Data.User;
                self.object_eeg_montage = o_data;
                self.state_loaded_eeg_montages = true;
            end
            
            %
            % Read Info
            %
            % get Info index
            for i_info = 1:length(self.object_eeg)
                try
                    self.object_eeg{i_info}(1).Info;
                    break
                end
            end
            
            % get Info:Admin index
            object_info = self.object_eeg{i_info};
            for i_admin = 1:length(object_info)
                try
                    object_info(i_admin).Info(1).Admin;
                    break
                end
            end
            
            % get Info:Name index
            for i_name = 1:length(object_info)
                try
                    object_info(i_name).Info(1).Name;
                    break
                end
            end
            
            % get Info:Personal index
            for i_pers = 1:length(object_info)
                try
                    object_info(i_pers).Info(1).Personal;
                    break
                end
            end
            
            % read Admin
            try
                self.subject_id = object_info(i_admin).Info(7).Admin.ID;
                self.state_loaded_eeg_admin = true;
            catch
                fprintf('[!] load EEG, Info::Admin not read from .eeg file.\n');
            end

            % read Name
            try
                self.subject_firstname = object_info(i_name).Info(1).Name.FirstName;
                self.subject_middlename = object_info(i_name).Info(3).Name.MiddleName;
                self.subject_lastname = object_info(i_name).Info(2).Name.LastName;
                self.subject_guid = object_info(i_name).Info(4).Name.PatientGUID;
                self.state_loaded_eeg_name = true;
            catch
                fprintf('[!] load EEG, Info::Name not read from .eeg file.\n');
            end

            % read Personal
            try
                self.subject_age = object_info(i_pers).Info(1).Personal.Age;
                self.subject_agelabel = object_info(i_pers).Info(2).Personal.AgeLabel;
                self.subject_birthdate = eval(object_info(i_pers).Info(3).Personal.BirthDate);
                self.subject_birthdatelabel = object_info(i_pers).Info(4).Personal.BirthDateLabel;
                if (self.subject_birthdate == 0)
                    self.subject_birthdatestr = 'Unknown';
                else
                    self.subject_birthdatestr = datestr(self.subject_birthdate,'mmm-dd-yy');
                end
                self.subject_gender = object_info(i_pers).Info(5).Personal.Gender;
                self.subject_genderlabel = object_info(i_pers).Info(6).Personal.GenderLabel;
                self.subject_handedness = object_info(i_pers).Info(7).Personal.Hand;
                self.subject_height = object_info(i_pers).Info(8).Personal.Height;
                self.subject_weight = object_info(i_pers).Info(9).Personal.Weight;
                self.state_loaded_eeg_personal = true;
            catch
                fprintf('[!] load EEG, Info::Personal not read from .eeg file.\n');
            end
            
            %
            % Read Study
            %
            % find Study
            idx_exists_Study = false(1,length(self.object_eeg));
            for i = 1:length(self.object_eeg)
                fieldn = fieldnames(self.object_eeg{i});
                if (strcmp(fieldn{1},'Study'))
                    idx_exists_Study(i) = true;
                end
            end
            %find Headbox (Level 1)
            if (any(idx_exists_Study))
                idx_exists_Headbox = false(1,length(self.object_eeg{idx_exists_Study}));
                for i = 1:length(self.object_eeg{idx_exists_Study})
                    instruct = self.object_eeg{idx_exists_Study}(i).Study;
                    if (isstruct(instruct))
                        fieldn = fieldnames(instruct);
                        if (strcmp(fieldn{1},'Headbox'))
                            idx_exists_Headbox(i) = true;
                        end
                    end
                end
            end
            % search and read from HB0 (Level 2)
            if (any(idx_exists_Headbox))
                for i = 1:length(self.object_eeg{idx_exists_Study}(idx_exists_Headbox).Study(1).Headbox)
                    instruct = self.object_eeg{idx_exists_Study}(idx_exists_Headbox).Study(1).Headbox(i).HB0;
                    if (isstruct(instruct))
                        fieldn = fieldnames(instruct);
                        if (strcmp(fieldn{1},'SamplingFreq'))
                            self.subject_frequency_sampling = str2double(instruct.SamplingFreq);
                        elseif (strcmp(fieldn{1},'HBSerialNumber'))
                            self.subject_headbox_sn = str2double(instruct.HBSerialNumber);
                        end
                    end
                end
            end
            
            try
                %find CreationTime (Level 1)
                if (any(idx_exists_Study))
                    idx_exists_l1 = false(1,length(self.object_eeg{idx_exists_Study}));
                    for i = 1:length(self.object_eeg{idx_exists_Study})
                        instruct = self.object_eeg{idx_exists_Study}(i).Study;
                        if (isstruct(instruct))
                            fieldn = fieldnames(instruct);
                            if (strcmp(fieldn{1},'CreationTime'))
                                idx_exists_l1(i) = true;
                            end
                        end
                    end
                end
                self.subject_study_creation_time = str2double(self.object_eeg{idx_exists_Study}(idx_exists_l1).Study(1).CreationTime);
            end
            
            try
                %find XLCreationTime (Level 1)
                if (any(idx_exists_Study))
                    idx_exists_l1 = false(1,length(self.object_eeg{idx_exists_Study}));
                    for i = 1:length(self.object_eeg{idx_exists_Study})
                        instruct = self.object_eeg{idx_exists_Study}(i).Study;
                        if (isstruct(instruct))
                            fieldn = fieldnames(instruct);
                            if (strcmp(fieldn{1},'XLCreationTime'))
                                idx_exists_l1(i) = true;
                            end
                        end
                    end
                end
                self.subject_study_xl_creation_time = self.object_eeg{idx_exists_Study}(idx_exists_l1).Study(1).XLCreationTime;
            end
            
            try
                %find ModificationTime (Level 1)
                if (any(idx_exists_Study))
                    idx_exists_l1 = false(1,length(self.object_eeg{idx_exists_Study}));
                    for i = 1:length(self.object_eeg{idx_exists_Study})
                        instruct = self.object_eeg{idx_exists_Study}(i).Study;
                        if (isstruct(instruct))
                            fieldn = fieldnames(instruct);
                            if (strcmp(fieldn{1},'ModificationTime'))
                                idx_exists_l1(i) = true;
                            end
                        end
                    end
                end
                self.subject_study_modification_time = str2double(self.object_eeg{idx_exists_Study}(idx_exists_l1).Study(1).ModificationTime);
            end
            
            try
                %find EpochLength (Level 1)
                if (any(idx_exists_Study))
                    idx_exists_l1 = false(1,length(self.object_eeg{idx_exists_Study}));
                    for i = 1:length(self.object_eeg{idx_exists_Study})
                        instruct = self.object_eeg{idx_exists_Study}(i).Study;
                        if (isstruct(instruct))
                            fieldn = fieldnames(instruct);
                            if (strcmp(fieldn{1},'EpochLength'))
                                idx_exists_l1(i) = true;
                            end
                        end
                    end
                end
                self.subject_study_epoch_length = str2double(self.object_eeg{idx_exists_Study}(idx_exists_l1).Study(1).EpochLength);
            end
            
            try
                %find WriterVersionMajor (Level 1)
                if (any(idx_exists_Study))
                    idx_exists_l1 = false(1,length(self.object_eeg{idx_exists_Study}));
                    for i = 1:length(self.object_eeg{idx_exists_Study})
                        instruct = self.object_eeg{idx_exists_Study}(i).Study;
                        if (isstruct(instruct))
                            fieldn = fieldnames(instruct);
                            if (strcmp(fieldn{1},'WriterVersionMajor'))
                                idx_exists_l1(i) = true;
                            end
                        end
                    end
                end
                self.subject_study_writer_version_major = str2double(self.object_eeg{idx_exists_Study}(idx_exists_l1).Study(1).WriterVersionMajor);
            end
            
            try
                %find WriterVersionMinor (Level 1)
                if (any(idx_exists_Study))
                    idx_exists_l1 = false(1,length(self.object_eeg{idx_exists_Study}));
                    for i = 1:length(self.object_eeg{idx_exists_Study})
                        instruct = self.object_eeg{idx_exists_Study}(i).Study;
                        if (isstruct(instruct))
                            fieldn = fieldnames(instruct);
                            if (strcmp(fieldn{1},'WriterVersionMinor'))
                                idx_exists_l1(i) = true;
                            end
                        end
                    end
                end
                self.subject_study_writer_version_minor = str2double(self.object_eeg{idx_exists_Study}(idx_exists_l1).Study(1).WriterVersionMinor);
            end

            try
                %find ProductVersionHigh (Level 1)
                if (any(idx_exists_Study))
                    idx_exists_l1 = false(1,length(self.object_eeg{idx_exists_Study}));
                    for i = 1:length(self.object_eeg{idx_exists_Study})
                        instruct = self.object_eeg{idx_exists_Study}(i).Study;
                        if (isstruct(instruct))
                            fieldn = fieldnames(instruct);
                            if (strcmp(fieldn{1},'ProductVersionHigh'))
                                idx_exists_l1(i) = true;
                            end
                        end
                    end
                end
                self.subject_study_product_version_high = str2double(self.object_eeg{idx_exists_Study}(idx_exists_l1).Study(1).ProductVersionHigh);
            end
            
            try
                %find ProductVersionLow (Level 1)
                if (any(idx_exists_Study))
                    idx_exists_l1 = false(1,length(self.object_eeg{idx_exists_Study}));
                    for i = 1:length(self.object_eeg{idx_exists_Study})
                        instruct = self.object_eeg{idx_exists_Study}(i).Study;
                        if (isstruct(instruct))
                            fieldn = fieldnames(instruct);
                            if (strcmp(fieldn{1},'ProductVersionLow'))
                                idx_exists_l1(i) = true;
                            end
                        end
                    end
                end
                self.subject_study_product_version_low = str2double(self.object_eeg{idx_exists_Study}(idx_exists_l1).Study(1).ProductVersionLow);
            end
            
            try
                %find OriginalStudyGUID (Level 1)
                if (any(idx_exists_Study))
                    idx_exists_l1 = false(1,length(self.object_eeg{idx_exists_Study}));
                    for i = 1:length(self.object_eeg{idx_exists_Study})
                        instruct = self.object_eeg{idx_exists_Study}(i).Study;
                        if (isstruct(instruct))
                            fieldn = fieldnames(instruct);
                            if (strcmp(fieldn{1},'OriginalStudyGUID'))
                                idx_exists_l1(i) = true;
                            end
                        end
                    end
                end
                self.subject_study_original_study_guid = self.object_eeg{idx_exists_Study}(idx_exists_l1).Study(1).OriginalStudyGUID;
            end
            
            try
                %find StudyGUID (Level 1)
                if (any(idx_exists_Study))
                    idx_exists_l1 = false(1,length(self.object_eeg{idx_exists_Study}));
                    for i = 1:length(self.object_eeg{idx_exists_Study})
                        instruct = self.object_eeg{idx_exists_Study}(i).Study;
                        if (isstruct(instruct))
                            fieldn = fieldnames(instruct);
                            if (strcmp(fieldn{1},'StudyGUID'))
                                idx_exists_l1(i) = true;
                            end
                        end
                    end
                end
                self.subject_study_guid = self.object_eeg{idx_exists_Study}(idx_exists_l1).Study(1).StudyGUID;
            end
            
            try
                %find StudyFileContents (Level 1)
                if (any(idx_exists_Study))
                    idx_exists_l1 = false(1,length(self.object_eeg{idx_exists_Study}));
                    for i = 1:length(self.object_eeg{idx_exists_Study})
                        instruct = self.object_eeg{idx_exists_Study}(i).Study;
                        if (isstruct(instruct))
                            fieldn = fieldnames(instruct);
                            if (strcmp(fieldn{1},'StudyFileContents'))
                                idx_exists_l1(i) = true;
                            end
                        end
                    end
                end
                self.subject_study_file_contents = str2double(self.object_eeg{idx_exists_Study}(idx_exists_l1).Study(1).StudyFileContents);
            end
            
%             %find CustomFields (Level 1)
%             if (any(idx_exists_Study))
%                 idx_exists_CustomFields = false(1,length(self.object_eeg{idx_exists_Study}));
%                 for i = 1:length(self.object_eeg{idx_exists_Study})
%                     instruct = self.object_eeg{idx_exists_Study}(i).Study;
%                     if (isstruct(instruct))
%                         fieldn = fieldnames(instruct);
%                         if (strcmp(fieldn{1},'CustomFields'))
%                             idx_exists_CustomFields(i) = true;
%                         end
%                     end
%                 end
%             end
%             % find Values (Level 2)
%             if (any(idx_exists_CustomFields))
%                 idx_exists_Values = false(1,length(self.object_eeg{idx_exists_Study}(idx_exists_CustomFields).Study));
%                 for i = 1:length(self.object_eeg{idx_exists_Study}(idx_exists_CustomFields).Study)
%                     instruct = self.object_eeg{idx_exists_Study}(idx_exists_CustomFields).Study(i).CustomFields;
%                     if (isstruct(instruct))
%                         fieldn = fieldnames(instruct);
%                         if (strcmp(fieldn{1},'Values'))
%                             idx_exists_Values(i) = true;
%                         end
%                     end
%                 end
%             end
%             % read recording start and end times (Level 3)
%             if (any(idx_exists_Values))
%                 for i = 1:length(self.object_eeg{idx_exists_Study}(idx_exists_CustomFields).Study(idx_exists_Values).CustomFields)
%                     instruct = self.object_eeg{idx_exists_Study}(idx_exists_CustomFields).Study(idx_exists_Values).CustomFields(i).Values;
%                     if (isstruct(instruct))
%                         fieldn = fieldnames(instruct);
%                         if (strcmp(fieldn{1},'RECORDINGENDTIME'))
%                             self.time_recording_end = str2double(instruct.RECORDINGENDTIME);
%                         elseif (strcmp(fieldn{1},'RECORDINGSTARTTIME'))
%                             self.time_recording_start = str2double(instruct.RECORDINGSTARTTIME);
%                         end
%                     end
%                 end
%             end
            
            
            self.state_loaded_eeg = true;
            %fprintf('\tDone.\n');
        end
        
%                                         
%   _|_|_|  _|_|_|_|_|    _|_|_|  
% _|            _|      _|        
%   _|_|        _|      _|        
%       _|      _|      _|        
% _|_|_|        _|        _|_|_|  
%                                 
  
        %
        % Load STC binary
        %
        function self = loadSTC(self)
            fprintf('\tLoading STC: %s ..\n',self.name_file_stc);
            BYTES_INT32 = 4; % number of bytes for int32
            BYTES_ID = 20; % number of bytes for magic number for file format identification
            BYTES_LOG = 320; % number of bytes for logs
            BYTES_HEADER = 52; % number of bytes after logs, before first block
            
            % magic number for identifying .stc format
            ID_STC = [-373878152;1297721419;1913685951;-1648510833;65537];
            
            % check format
            f_stc = fopen(self.name_file_stc,'r');
            stc_id = fread(f_stc,[BYTES_ID/BYTES_INT32,1],'int32');
            if (~all(stc_id == ID_STC))
                fprintf(2,'[!] Warning in %s.loadSTC: file %s does not match filetype identifier\n',self.name_script,self.name_file_stc);
            end
            
            % read binary
            
            % creation time
            stc_creation_time = fread(f_stc,[1,1],'int32');
            %fprintf('\tEEG Creation Time: %i\n',eeg_creation_time);
            
            % 8 bytes of zeros
            null = fread(f_stc,[1,1],'int32');
            null = fread(f_stc,[1,1],'int32');
            stc_log = char(fread(f_stc,[BYTES_LOG,1],'int8'));
            
            % read number of .erd and .etc data subfiles
            n_data_files = fread(f_stc,[1,1],'int32');
            
            % read 56 bytes
            header = fread(f_stc,[BYTES_HEADER,1],'int8');
%             unknown = fread(f_stc,[BYTES_HEADER,1],'int8');
%             f_tmp_bin = fopen(sprintf('tmp56_%s.bin',replace(self.subject_id,' ','')),'w');
%             fwrite(f_tmp_bin,unknown);
%             fclose(f_tmp_bin);
            
            stc_filename = cell(1,n_data_files+1);
            stc_stamp_start = nan(1,n_data_files+1);
            stc_stamp_end = nan(1,n_data_files+1);
            stc_index = nan(1,n_data_files+1);
            stc_n_samples = nan(1,n_data_files+1);
            stc_n_files = n_data_files + 1;
            for i = 1:(n_data_files+1)
                % read block
                BYTES_FILENAME = 256; % number of bytes of repeating block
                fname = char(fread(f_stc,[BYTES_FILENAME,1],'int8'))';
                
                % trim trailing whitespace
                cond_pass = true;
                while(cond_pass)
                    cond_pass = (isspace(fname(end)));
                    if (cond_pass)
                        fname(end) = [];
                    end
                end
                stc_filename{i} = fname;
                
                % read stamp positions and numbers of samples
                stc_stamp_start(i) = fread(f_stc,[1,1],'int32');
                stc_stamp_end(i) = fread(f_stc,[1,1],'int32');
                stc_index(i) = fread(f_stc,[1,1],'int32');
                stc_n_samples(i) = fread(f_stc,[1,1],'int32');
            end
            self.object_stc.filename = stc_filename;
            self.object_stc.stamp_start = stc_stamp_start;
            self.object_stc.stamp_end = stc_stamp_end;
            self.object_stc.index = stc_index;
            self.object_stc.n_samples = stc_n_samples;
            self.object_stc.n_files = stc_n_files;
            %BYTES_BLOCK
            
            % close file
            fclose(f_stc);
            self.state_loaded_stc = true;
        end
        
%                                           
% _|_|_|_|  _|      _|  _|_|_|_|_|  
% _|        _|_|    _|      _|      
% _|_|_|    _|  _|  _|      _|      
% _|        _|    _|_|      _|      
% _|_|_|_|  _|      _|      _|      
%                 

        %
        % Load ENT binary
        %
        function self = loadENT(self)
            fprintf('\tLoading ENT: %s ..\n',self.name_file_ent);
            BYTES_INT32 = 4; % number of bytes for int32
            BYTES_ID = 20; % number of bytes for magic number for file format identification
            BYTES_LOG = 320; % number of bytes for logs
                        
            % magic number for identifying .stc format
            ID_ENT = [-905246829;298899349;-1610599761;-1521198300;65539];
            
            % check format
            f_ent = fopen(self.name_file_ent,'r');
            ent_id = fread(f_ent,[BYTES_ID/BYTES_INT32,1],'int32');
            if (~all(ent_id == ID_ENT))
                fprintf(2,'[!] Warning in %s.loadENT: file %s does not match filetype identifier\n',self.name_script,self.name_file_ent);
            end
            
            % read binary
            
            % creation time
            stc_creation_time = fread(f_ent,[1,1],'int32');
            %fprintf('\tEEG Creation Time: %i\n',eeg_creation_time);
            
            % 8 bytes of zeros
            null = fread(f_ent,[1,1],'int32');
            null = fread(f_ent,[1,1],'int32');
            ent_log = char(fread(f_ent,[BYTES_LOG,1],'int8'));
            
            % read ascii
            ent = char(fread(f_ent,'int8'))';

            % close file
            fclose(f_ent);
            
            [ent_cleaned] = self.clean_txt(ent);
            %disp(ent_cleaned);
            %self.ent_cleaned = ent_cleaned;
            
            oent_list = {};
            for i = 1:length(ent_cleaned)
                [oent,~] = self.parse_obj(1,ent_cleaned{i});
                oent_list = [oent_list, {oent}];
            end
            self.object_ent = oent_list;
            
%             fprintf('ent_cleaned length: %i\n',length(ent_cleaned))
%             fprintf('ent length: %i\n',length(ent))
%             [oent,~] = self.parse_obj(1,ent_cleaned);
%             self.object_ent = oent;
            
            % load success
            self.state_loaded_ent = true;
        end
        
%                                           
% _|      _|  _|_|_|_|_|    _|_|_|  
% _|      _|      _|      _|        
% _|      _|      _|      _|        
%   _|  _|        _|      _|        
%     _|          _|        _|_|_|  
%                                   
        %
        % Load VTC binary
        %
        function self = loadVTC(self)
            if (~exist(self.name_file_vtc,'file'))
                fprintf(2,'[!] loadVTC cannot find file: %s\n',self.name_file_vtc);
                return
            end
            
            % ANSI time epoch starts at January 1st, 1601                                    
            % UTC - 5 hours (before DST)
            BOSTON_UTC_OFFSET = 5; %hours
            HOURS_PER_DAY = 24;
            MINUTES_PER_HOUR = 60;
            SECONDS_PER_MINUTE = 60;
            ANSI_PIVOT_YEAR = 1601;
            ANSI_PIVOT_MONTH = 1;
            ANSI_PIVOT_DAY = 1;
            pivot_days = datenum(ANSI_PIVOT_YEAR,ANSI_PIVOT_MONTH,ANSI_PIVOT_DAY) - BOSTON_UTC_OFFSET/HOURS_PER_DAY;
            secs_per_day = HOURS_PER_DAY * MINUTES_PER_HOUR * SECONDS_PER_MINUTE;

            fprintf('\tLoading VTC: %s ..\n',self.name_file_vtc);
            BYTES_INT32 = 4; % number of bytes for int32
            BYTES_ID = 20; % number of bytes for magic number for file format identification
            BYTES_LOG = 320; % number of bytes for logs
            ID_VTC = [1541647521;1254138416;1699321002;-1594479601;1114113];
            
            
             % check format
            f_vtc = fopen(self.name_file_vtc,'r');
            vtc_id = fread(f_vtc,[BYTES_ID/BYTES_INT32,1],'int32');
            if (~all(vtc_id == ID_VTC))
                fprintf(2,'[!] Warning in %s.loadENT: file %s does not match filetype identifier\n',self.name_script,self.name_file_vtc);
            end
            
            f_count = 1;                                                                     
            while (~feof(f_vtc))                                                             
                vtc_fname_t = fread(f_vtc,[61,1],'int8');                                    
                null = fread(f_vtc,[200,1],'int8');                                          
                if (feof(f_vtc))                                                             
                    break                                                                    
                end                                                                          
                vtc_fname{f_count,1} = char(vtc_fname_t(vtc_fname_t~=0))';                   
                null = fread(f_vtc,[16,1],'int8');                                           
                vtc_start(f_count,1) = fread(f_vtc,[1,1],'int64');                           
                vtc_end(f_count,1) = fread(f_vtc,[1,1],'int64');                             
                f_count = f_count + 1;                                                       
            end                                                                              
            fclose(f_vtc);                                                                   
            vtc_start_days = vtc_start/(secs_per_day * 1e7) + pivot_days;                    
            vtc_end_days = vtc_end/(secs_per_day * 1e7) + pivot_days;                        
            %fprintf('Checking for Daylight Savings Time..\n')                                
            % Check Daylight Savings Time                                                    
            for i = 1:length(vtc_start_days)                                              
                if (isdst( datetime(datestr(vtc_start_days(i)),'TimeZone','America/New_York') ))
                    vtc_start_days(i) = vtc_start(i)/(secs_per_day * 1e7) + pivot_days + 1/24;
                end                                                                          
            end                                                                              
            for i = 1:length(vtc_end_days)                                                
                if (isdst( datetime(datestr(vtc_end_days(i)),'TimeZone','America/New_York') ))
                    vtc_end_days(i) = vtc_end(i)/(secs_per_day * 1e7) + pivot_days + 1/24;   
                end                                                                          
            end                                                                                 

            datefmt = 'mmmm dd, yyyy HH:MM:SS.FFF AM';
            strings_start = cell(size(vtc_fname));
            strings_end = cell(size(vtc_fname));
            for i = 1:length(vtc_start_days)
                strings_start{i} = datestr(vtc_start_days(i),datefmt);
                strings_end{i} = datestr(vtc_end_days(i),datefmt);
                %fprintf('%s\t%s\t%s\n',vtc_fname{i},datestr(vtc_start_days(i),datefmt),datestr(vtc_end_days(i),datefmt))
            end
            
            ovtc = struct();
            ovtc.filenames = vtc_fname;
            ovtc.strings_start = strings_start;
            ovtc.strings_end = strings_end;
            ovtc.strings_datefmt = datefmt;
            ovtc.days_start = vtc_start_days;
            ovtc.days_end = vtc_end_days;
            self.object_vtc = ovtc;
            
            
            % close file
            %fclose(f_vtc);
            
            % load success
            self.state_loaded_vtc = false;
        end
        
%                                         
% _|_|_|_|  _|_|_|_|_|    _|_|_|  
% _|            _|      _|        
% _|_|_|        _|      _|        
% _|            _|      _|        
% _|_|_|_|      _|        _|_|_|  
%   
        
        %
        % Load ETC binary
        %
        function self = loadETC(self)
            if (~self.state_loaded_stc)
                fprintf(2,'[!] loadETC cannot continue because the STC file was not loaded successfully.\n')
                return
            end
            
            self.state_loaded_etc = false(1,self.object_stc.n_files);
            erd_ptr_all = cell(1,self.object_stc.n_files);
            stamp_start_all = cell(1,self.object_stc.n_files);
            index_start_all = cell(1,self.object_stc.n_files);
            n_samples_all = cell(1,self.object_stc.n_files);
            unknown_all = cell(1,self.object_stc.n_files);
            for i = 1:self.object_stc.n_files
                fname_etc = sprintf('%s/%s.etc',self.name_dir,self.object_stc.filename{i});
                if (~exist(fname_etc,'file'))
                    fprintf(2,'[!] loadETC cannot find file: %s\n',fname_etc);
                    return
                else
                    fprintf(1,'\tLoading ETC: %s\n',fname_etc);
                    %
                    %   Main load .etc section
                    %
                    ID_ETC = [-905246830;298899349;-1610599761;-1521198300;65539];
                    BYTES_INT32 = 4; % number of bytes for int32
                    BYTES_ID = 20; % number of bytes for magic number for file format identification
                    BYTES_LOG = 320; % number of bytes for logs

                    % check format
                    f_etc = fopen(fname_etc,'r');
                    etc_id = fread(f_etc,[BYTES_ID/BYTES_INT32,1],'int32');
                    if (~all(etc_id == ID_ETC))
                        fprintf(2,'[!] Warning in %s.loadETC: file %s does not match filetype identifier\n',self.name_script,fname_etc);
                    end
                    % read binary

                    % creation time
                    etc_creation_time = fread(f_etc,[1,1],'int32');
                    %fprintf('\tEEG Creation Time: %i\n',eeg_creation_time);

                    % 8 bytes of zeros
                    null = fread(f_etc,[1,1],'int32');
                    null = fread(f_etc,[1,1],'int32');
                    etc_log = char(fread(f_etc,[BYTES_LOG,1],'int8'));
                    
                    % read 16 byte chunks
                    f_count = 1;
                    erd_ptr = [];
                    stamp_start = [];
                    index_start = [];
                    n_samples = [];
                    unknown = [];
                    while (~feof(f_etc))                                                             
                        erd_ptr = [erd_ptr,fread(f_etc,[1,1],'int32')];                                    
                        stamp_start = [stamp_start,fread(f_etc,[1,1],'int32')];
                        index_start = [index_start,fread(f_etc,[1,1],'int32')];
                        n_samples = [n_samples,fread(f_etc,[1,1],'int16')];
                        unknown = [unknown,fread(f_etc,[1,1],'int16')];
                        if (feof(f_etc))                                                             
                            break                                                                    
                        end                             
                        f_count = f_count + 1;                                                       
                    end                                                                              
                    fclose(f_etc);
                end
                erd_ptr_all{i} = erd_ptr;
                stamp_start_all{i} = stamp_start;
                index_start_all{i} = index_start;
                n_samples_all{i} = n_samples;
                unknown_all{i} = unknown;
                self.state_loaded_etc(i) = true;
            end
            
            oetc = struct();
            oetc.erd_ptr = erd_ptr_all;
            oetc.stamp_start = stamp_start_all;
            oetc.index_start = index_start_all;
            oetc.n_samples = n_samples_all;
            oetc.unknown = unknown_all;
            self.object_etc = oetc;
        end
        
%                                       
% _|_|_|_|  _|_|_|    _|_|_|    
% _|        _|    _|  _|    _|  
% _|_|_|    _|_|_|    _|    _|  
% _|        _|    _|  _|    _|  
% _|_|_|_|  _|    _|  _|_|_|    
%  
        
        %
        % Load ERD binary
        %
        function self = loadERD(self)
            ID_ERD = [-905246831;298899349;-1610599761;-1521198300;65545];
        end
    end
    
    methods
        %
        % Constructor
        %
        function self = Openxlt(indir)
            % init
            self.name_script = 'Openxlt_v0';
            
            % set up input directory
            self.name_dir = indir;
            % remove trailing slash
            if (endsWith(self.name_dir,'/'))
                self.name_dir = self.name_dir(1:(end-1));
            end
            
            % find file name root
            suffix = '.eeg';
            eeg_fname_list = self.carveF(self.name_dir,suffix);
            if (length(eeg_fname_list) > 1)
                fprintf('[*] %s warning: more than one %s file found.\n',self.name_script,suffix);
                disp(eeg_fname_list);
            end
            eeg_fname_list = eeg_fname_list{1};
            eeg_fname_list = strsplit(eeg_fname_list,self.name_dir);
            eeg_fname_list = eeg_fname_list{end};
            % remove leading slash
            if (startsWith(eeg_fname_list,'/'))
                eeg_fname_list = eeg_fname_list(2:end);
            end
            self.name_file_root = eeg_fname_list(1:(end-length(suffix)));
        end
        
        %
        % Main load function
        %
        function self = load(self)
            % read .eeg - main file
            self.name_file_eeg = self.checkFile('.eeg');
            self = self.loadEEG();
            
            % read .stc - index file for .etc and .erd data files
            self.name_file_stc = self.checkFile('.stc');
            self = self.loadSTC();
            
            % read .ent - annotation and montage file
            self.name_file_ent = self.checkFile('.ent');
            self = self.loadENT();
            
            % read .vtc - video index file
            self.name_file_vtc = self.checkFile('.vtc');
            self = self.loadVTC();
            
            % further reading and loading
            self = self.parseMontageFromEEG();
            self = self.loadETC();
        end
    end
end
