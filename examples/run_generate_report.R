
# Generate reporting results --------------
# in IAMC format

## from a .dat file --------------

devtools::load_all()

## -- store the database path, name, and scenarios in a variable.

GCAMv = 'v8.2'   # "vEurope7.2"#'vScenarioMIPCMIP7'  #'v7.2'

# terms to ignore -- ones that the user introduced, are policies rather than physical quantities
ignr <- c("ceiling", "coal-elec-constraint", "CO2_NearTerm", "wind_offshore-trial-supply", "globalCO2_LTG",
          # "regional natural gas", "traded LNG", "traded pipeline gas", "regional coal", "traded coal", "regional oil", "traded oil",  ### REMOVE THIS LATER!!
          "bld_coal") #

filetyp <- "CSV"

fls <- grep(".dat", list.files("output/"), value = T)
fls <- grep("ngfs.*.dat", list.files("output/"), value = T)
print(fls)

## -- choose a project name
prjname <- file.path("output", fls[1]); prjname

outflnm <- "output/all_ngfs_1p5_26Apr13"; outflnm

generate_report(prj_name = prjname,
                GCAM_version = GCAMv,
                # desired_regions = c("USA"),
                # desired_variables = c('Emissions*', 'Primary*', 'Secondary*', 'Final*','Populat*', 'Ag*',
                #                       'Capacity*','GDP*', 'Land*', 'Carbon*','Price|Carbon*','Temp*'
                #                       'Consumption*', 'Fertilizer*', 'Energy*', 'Food*', 'Forest*', 'Gross*', 'Production*', 'Resource*', 'Sale*', 'Stock*', 'Water*', 'Yield*', ##, 'Trade|Primary*', 'Efficiency*'
                #                       'Revenue*', 'Income*', 'Investment*'  ##'Lifetime*',
                # ),
                # desired_variables = c('Emissions*'),
                # desired_variables = c('Emissions*', 'Primary*', 'Secondary*', 'Final*','Populat*','Price|Carbon*', 'Carbon*'),  ## , 'Energy*', 'Land*'
                ignore = ignr,
                save_output = filetyp, launch_ui = F, output_file = outflnm)


## from a database ------------------

devtools::load_all()



## -- store the database path, name, and scenarios in a variable.

GCAMv <- 'v8.2'

ignr <- c("ceiling", "coal-elec-constraint", "CO2_NearTerm", "wind_offshore-trial-supply", "globalCO2_LTG",
          # "regional natural gas", "traded LNG", "traded pipeline gas", "regional coal", "traded coal", "regional oil", "traded oil",  ### REMOVE THIS LATER!!
          "bld_coal") # , "CO2 removal"


dbpath <- "C:/Users/amille17/xpsLocal"
dbname <- "db_chinaGas_BAU_RH_251122"

## -- choose a project name
prjname <- "chinaGas_BAU_RH_25Dec16.dat"

outflnm <- "output/chinaGas_BAU_RH_25Dec16"; outflnm

generate_report(db_path = dbpath, db_name = dbname, ##scenarios = scen,
                prj_name = prjname,GCAM_version = GCAMv,
                # desired_regions = c('China', 'USA'),
                # desired_variables = c('Price*'),
                ignore = ignr,
                save_output = TRUE, launch_ui = FALSE, output_file = outflnm)
