# library(devtools)
# devtools::load_all()
library(gcamreport)

## -- store the database path, name, and scenarios in a variable.
dbpath <- "/Users/xiangwenfu/Princeton Dropbox/Xiangwen Fu/Study/postdoc/GCAM/gcam-v7.1/output"
dbname <- "db_test_ref_241002"
scen <- c("test_ref_241002")
GCAMv <- "v7.1"

## -- choose a project name
prjname <- "test_ref_241002.dat"

## -- generate the reporting dataset until 2050 for EU-12 and EU-15 for all the
## -- Agricultural variables, save the output in .RData, .csv and .xlsx format,
## -- and lunch the user interface
generate_report(db_path = dbpath, db_name = dbname, scenarios = scen,
                prj_name = prjname, final_year = 2060, GCAM_version = GCAMv,
              #  desired_regions = c('China','USA'),
                desired_variables = c('Sales*', 'Stocks*'),
                save_output = TRUE, launch_ui = FALSE,
                output_file=paste0("output/", scen))
