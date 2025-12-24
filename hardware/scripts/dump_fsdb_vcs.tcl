global env
fsdbDumpfile "$env(project_name).fsdb"
fsdbDumpvars 0 "tb_$env(project_name)" "+all"
fsdbDumpMDA
run
