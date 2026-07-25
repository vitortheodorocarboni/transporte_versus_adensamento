################################################################################
##################################            ##################################
###################### 06.01) DOWNLOAD SPTRANS GTFS FEED #######################
##################################            ##################################
################################################################################

################################################################################
##### I. Packages
################################################################################

# # Installing packages
# install.packages("httr")

# Loading libraries
library(httr)


################################################################################
##### II. Directories and files
################################################################################

# Loading project paths
source(file.path("scripts", "_config", "paths.R"))

# Setting r5r input data directory
r5r_directory <- raw_path("travel_times", "r5r_core")

# Setting GTFS output file path
gtfs_output <- file.path(r5r_directory, "sptrans_gtfs.zip")

################################################################################
##### III. Source information
################################################################################

# Setting SPTrans OlhoVivo API authentication endpoint
auth_url <- "http://api.olhovivo.sptrans.com.br/v2.1/Login/Autenticar"

# Setting SPTrans GTFS download endpoint
gtfs_url <- "http://www.sptrans.com.br/umbraco/Surface/PerfilDesenvolvedor/BaixarGTFS"

# Setting SPTrans developer API token
api_token <- "b4270141b24e008e88b256b1bc5a05ba492a8da5ab86a9f3b6d4edf7adaea4d3"


################################################################################
##### IV. Downloading data
################################################################################

# Creating r5r input data directory
dir.create(
  path         = r5r_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Authenticating with the SPTrans OlhoVivo API
auth_response <- POST(
  url   = auth_url,
  query = list(token = api_token)
)

# Extracting session cookies from the authentication response
session_cookies <- cookies(auth_response)

# Downloading the GTFS feed
GET(
  url = gtfs_url,
  set_cookies(
    .cookies = setNames(
      object = session_cookies$value,
      nm     = session_cookies$name
    )
  ),
  write_disk(
    path      = gtfs_output,
    overwrite = TRUE
  )
)
