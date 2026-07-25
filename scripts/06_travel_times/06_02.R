################################################################################
##################################            ##################################
################ 06.02) DOWNLOAD AND CLIP OSM PBF FOR SÃO PAULO ################
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

# Setting staging directory
staging_directory <- raw_path("travel_times")

# Setting tools directory
tools_directory <- raw_path("travel_times", "_tools")

# Setting full Sudeste PBF staging path
sudeste_pbf <- file.path(staging_directory, "sudeste.osm.pbf")

# Setting clipped São Paulo city PBF output path
sao_paulo_pbf <- file.path(r5r_directory, "sao_paulo.osm.pbf")

# Setting osmconvert64.exe local path
osmconvert_path <- file.path(tools_directory, "osmconvert64.exe")


################################################################################
##### III. Source information
################################################################################

# Setting Geofabrik Sudeste reference page
geofabrik_page <- "https://download.geofabrik.de/south-america/brazil/sudeste.html"

# Setting Geofabrik Sudeste OSM PBF URL
osm_url <- "https://download.geofabrik.de/south-america/brazil/sudeste-260101.osm.pbf"

# Setting osmconvert64.exe download URL
osmconvert_url <- "http://m.m.i24.cc/osmconvert64.exe"

# Setting São Paulo city bounding box from GeoSampa metadata record
sp_bbox <- list(
  west  = -46.83,
  east  = -46.36,
  south = -24.01,
  north = -23.36
)

# Setting security margin around the bounding box
bbox_margin <- 0.05

# Computing final clipping bounding box with margin
clip_bbox <- list(
  west  = sp_bbox$west  - bbox_margin,
  east  = sp_bbox$east  + bbox_margin,
  south = sp_bbox$south - bbox_margin,
  north = sp_bbox$north + bbox_margin
)


################################################################################
##### IV. Downloading osmconvert
################################################################################

# Creating tools directory
dir.create(
  path         = tools_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Validating any previously cached osmconvert64.exe
if (file.exists(osmconvert_path)) {

  cached_size_ok <- file.info(osmconvert_path)$size > 0

  cached_header  <- readBin(
    con  = osmconvert_path,
    what = "raw",
    n    = 2
  )
  cached_magic_ok <- identical(cached_header, charToRaw("MZ"))

  if (!cached_size_ok || !cached_magic_ok) {
    message("Cached osmconvert64.exe is invalid; removing it.")
    file.remove(osmconvert_path)
  }
}

# Downloading osmconvert64.exe if not already cached
if (!file.exists(osmconvert_path)) {

  message("Downloading osmconvert64.exe ...")
  osmconvert_response <- GET(
    url = osmconvert_url,
    user_agent("Mozilla/5.0"),
    write_disk(
      path      = osmconvert_path,
      overwrite = TRUE
    ),
    progress()
  )

} else {
  message("Using cached osmconvert64.exe.")
}


################################################################################
##### V. Downloading Sudeste OSM PBF
################################################################################

# Creating r5r and staging directories
dir.create(
  path         = r5r_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)
dir.create(
  path         = staging_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Downloading the Sudeste OSM PBF
message("Downloading Geofabrik Sudeste OSM PBF ...")
osm_response <- RETRY(
  verb         = "GET",
  url          = osm_url,
  user_agent("Mozilla/5.0"),
  write_disk(
      path      = sudeste_pbf,
      overwrite = TRUE
  ),
  progress(),
  times        = 5,
  pause_base   = 5,
  pause_cap    = 60,
  terminate_on = c(404)
)


sudeste_size_mb <- file.info(sudeste_pbf)$size / 1e6


################################################################################
##### VI. Clipping to São Paulo bounding box
################################################################################

# Removing any previous clipped output
if (file.exists(sao_paulo_pbf)) {
  file.remove(sao_paulo_pbf)
}

# Converting Windows paths to 8.3 short names
sudeste_short   <- utils::shortPathName(normalizePath(
  path     = sudeste_pbf,
  winslash = "\\",
  mustWork = TRUE
))
r5r_dir_short   <- utils::shortPathName(normalizePath(
  path     = r5r_directory,
  winslash = "\\",
  mustWork = TRUE
))
sao_paulo_short <- file.path(r5r_dir_short, "sao_paulo.osm.pbf")

# Building osmconvert command-line arguments
osmconvert_args <- c(
  sudeste_short,
  sprintf(
    "-b=%f,%f,%f,%f",
    clip_bbox$west,
    clip_bbox$south,
    clip_bbox$east,
    clip_bbox$north
  ),
  paste0("-o=", sao_paulo_short)
)

# Reporting the bounding box being applied
message(
  "Clipping Sudeste PBF to São Paulo bounding box: ",
  "W=", clip_bbox$west, ", S=", clip_bbox$south, ", ",
  "E=", clip_bbox$east, ", N=", clip_bbox$north, " ..."
)

# Running osmconvert
osmconvert_output <- system2(
  command = osmconvert_path,
  args    = osmconvert_args,
  stdout  = TRUE,
  stderr  = TRUE
)

osmconvert_status <- attr(x = osmconvert_output, which = "status")


clipped_size_mb <- file.info(sao_paulo_pbf)$size / 1e6

# Reporting clipping summary
message(
  "São Paulo PBF produced successfully. ",
  "Staged Sudeste: ", round(sudeste_size_mb, 1), " MB. ",
  "Clipped São Paulo: ", round(clipped_size_mb, 1), " MB."
)
