# OpenXLT
Matlab Class for reading Natus Neuroworks .EEG files

Openxlt
 --------------------------------------------------------------------------
 
    Openxlt
 
 --------------------------------------------------------------------------
 
    Intro
 
        Load XLTEK .eeg data.
 
    Usage
 
        o = Openxlt('test/raw_data');
        o = o.load();
 
    Author
 
        Jiarui Wang :: jwang04@g.harvard.edu
 
 --------------------------------------------------------------------------
Class Details
Sealed	false
Construct on load	false
Constructor Summary
Openxlt	init 
Property Summary
name_dir	 
name_file_eeg	 
name_file_ent	 
name_file_root	 
name_file_stc	 
name_file_vtc	 
name_script	filenames 
object_eeg	structs 
object_eeg_list	main file, additional properties 
object_eeg_montage	list of electrode labels 
object_ent	list of annotations 
object_etc	list of erd data file pointers 
object_stc	list of etc and erd data files 
object_vtc	list of video files 
state_loaded_eeg	load states 
state_loaded_eeg_admin	 
state_loaded_eeg_montages	 
state_loaded_eeg_name	 
state_loaded_eeg_personal	 
state_loaded_ent	 
state_loaded_etc	 
state_loaded_stc	 
state_loaded_vtc	 
subject_age	 
subject_agelabel	 
subject_birthdate	 
subject_birthdatelabel	 
subject_birthdatestr	 
subject_firstname	 
subject_frequency_sampling	 
subject_gender	 
subject_genderlabel	 
subject_guid	 
subject_handedness	 
subject_headbox_sn	 
subject_height	 
subject_id	information 
subject_lastname	 
subject_middlename	 
subject_study_creation_time	 
subject_study_epoch_length	 
subject_study_file_contents	 
subject_study_guid	 
subject_study_modification_time	 
subject_study_original_study_guid	 
subject_study_product_version_high	 
subject_study_product_version_low	 
subject_study_writer_version_major	 
subject_study_writer_version_minor	 
subject_study_xl_creation_time	 
subject_weight	 
Method Summary
 	load	read .eeg - main file 
