/*
    Fails for every delivered ALR file that the connector cannot place
    (TUVA-164), listing each file's delivery_id and the performance year,
    period and alr_file_type parsed from its name. Benchmark AALRs never fail:
    their parameters are derived (aalr_file_parameters). Any other unmatched
    file is left out of aalr_history and aalr_governing_file, so its months
    are missing from enrollment until a release adds its mssp_file_parameters
    row. See the README's "Files with no parameters row".
*/
{{ alr_files_without_file_parameters() }}
