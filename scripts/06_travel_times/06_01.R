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

# Setting temporary GTFS download file path
gtfs_temporary_output <- tempfile(
  pattern = "sptrans_gtfs_",
  fileext = ".zip"
)


################################################################################
##### III. Source information
################################################################################

# Setting SPTrans OlhoVivo API authentication endpoint
auth_url <- "https://api.olhovivo.sptrans.com.br/v2.1/Login/Autenticar"

# Setting SPTrans GTFS download endpoint
gtfs_url <- "https://www.sptrans.com.br/umbraco/Surface/PerfilDesenvolvedor/BaixarGTFS"

# Setting SPTrans developer API token environment variable
api_token_environment_variable <- "SPTRANS_API_TOKEN"

# Retrieving SPTrans developer API token from the user environment
api_token <- Sys.getenv(
  x     = api_token_environment_variable,
  unset = ""
)

# Setting expected GTFS files (full standard set provided by SPTrans)
expected_gtfs_files <- c(
  "agency.txt",
  "calendar.txt",
  "fare_attributes.txt",
  "fare_rules.txt",
  "frequencies.txt",
  "routes.txt",
  "shapes.txt",
  "stop_times.txt",
  "stops.txt",
  "trips.txt"
)


################################################################################
##### IV. Downloading data
################################################################################

# Creating r5r input data directory
dir.create(
  path         = r5r_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Extending R download timeout for the GTFS file
options(timeout = max(600, getOption("timeout")))

# Stopping if the SPTrans developer API token is unavailable
if (!nzchar(api_token)) {
  stop(
    paste0(
      "Environment variable ",
      api_token_environment_variable,
      " is not configured."
    ),
    call. = FALSE
  )
}

# Authenticating with the SPTrans OlhoVivo API
auth_response <- POST(
  url   = auth_url,
  query = list(token = api_token)
)

# Stopping if the SPTrans authentication request fails
stop_for_status(
  x    = auth_response,
  task = "authenticate with the SPTrans OlhoVivo API"
)

# Reading the authentication result
auth_result <- content(
  x        = auth_response,
  as       = "text",
  encoding = "UTF-8"
)

# Stopping if the SPTrans API rejects the developer token
if (!identical(tolower(trimws(auth_result)), "true")) {
  stop(
    "SPTrans OlhoVivo API authentication was rejected.",
    call. = FALSE
  )
}

# Extracting session cookies from the authentication response
session_cookies <- cookies(auth_response)

# Stopping if the authentication response does not provide session cookies
if (nrow(session_cookies) == 0) {
  stop(
    "SPTrans authentication did not return session cookies.",
    call. = FALSE
  )
}

# Downloading the GTFS feed to a temporary file
gtfs_response <- GET(
  url = gtfs_url,
  set_cookies(
    .cookies = setNames(
      object = session_cookies$value,
      nm     = session_cookies$name
    )
  ),
  write_disk(
    path      = gtfs_temporary_output,
    overwrite = TRUE
  )
)

# Stopping if the SPTrans GTFS download request fails
stop_for_status(
  x    = gtfs_response,
  task = "download the SPTrans GTFS feed"
)

# Stopping if the downloaded GTFS archive is empty
if (
  !file.exists(gtfs_temporary_output) ||
  file.info(gtfs_temporary_output)$size == 0
) {
  stop(
    "SPTrans GTFS download returned an empty file.",
    call. = FALSE
  )
}

# Reading the downloaded GTFS archive contents
gtfs_archive_contents <- unzip(
  zipfile = gtfs_temporary_output,
  list    = TRUE
)

# Extracting downloaded GTFS file names
downloaded_gtfs_files <- basename(gtfs_archive_contents$Name)

# Identifying expected GTFS files missing from the downloaded archive
missing_gtfs_files <- setdiff(
  x = expected_gtfs_files,
  y = downloaded_gtfs_files
)

# Stopping if the downloaded archive does not contain the expected GTFS files
if (length(missing_gtfs_files) > 0) {
  file.remove(gtfs_temporary_output)

  stop(
    paste0(
      "SPTrans GTFS archive is missing expected files: ",
      paste(missing_gtfs_files, collapse = ", "),
      "."
    ),
    call. = FALSE
  )
}

# Copying the validated GTFS archive to the r5r input directory
gtfs_saved <- file.copy(
  from      = gtfs_temporary_output,
  to        = gtfs_output,
  overwrite = TRUE
)

# Stopping if the validated GTFS archive cannot be saved
if (!isTRUE(gtfs_saved)) {
  stop(
    "Validated SPTrans GTFS archive could not be saved.",
    call. = FALSE
  )
}

# Removing the temporary GTFS download file
file.remove(gtfs_temporary_output)

# Reporting success
message(
  "SPTrans GTFS downloaded and validated successfully. ",
  "Archive size: ", round(file.info(gtfs_output)$size / 1e6, 1), " MB."
)
