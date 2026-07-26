################################################################################
##################################            ##################################
###################### PROJECT PATHS CONFIGURATION FILE ########################
##################################            ##################################
################################################################################

################################################################################
##### I. Packages
################################################################################

# # Installing packages
# install.packages("arrow")
# install.packages("geoarrow")
# install.packages("sf")
# install.packages("tidyverse")

# Loading libraries
library(arrow)
library(geoarrow)
library(sf)
library(tidyverse)


################################################################################
##### I. Functions
################################################################################

# Creating a function to find the project root directory
find_project_root <- function(start = getwd()) {
  
  # Normalizing the initial directory path
  current <- normalizePath(
    path     = start,
    winslash = "/",
    mustWork = TRUE
  )
  
  # Walking up the folder tree until the project root marker is found
  repeat {
    
    # Returning the current directory if it contains the project root marker
    if (file.exists(file.path(current, ".here"))) {
      return(current)
    }
    
    # Retrieving the parent directory
    parent <- dirname(current)
    
    # Stopping execution if the root marker cannot be found
    if (identical(parent, current)) {
      stop(
        "Project root marker '.here' was not found from: ",
        normalizePath(
          path     = start,
          winslash = "/",
          mustWork = TRUE
        )
      )
    }
    
    # Updating the current directory
    current <- parent
  }
}

# Creating a function to build paths from the project root directory
project_path <- function(...) {
  
  # Combining the project root directory with path components
  file.path(project_root, ...)
}

# Creating a function to build paths from the project root directory
data_path <- function(...) {
  
  # Combining the project root directory with the data directory
  file.path(project_root, "data", ...)
}

# Creating a function to build paths from the raw data directory
raw_path <- function(...) {
  
  # Combining the project root directory with the raw data directory
  file.path(project_root, "data", "raw", ...)
}

# Creating a function to build paths from the processed data directory
processed_path <- function(...) {
  
  # Combining the project root directory with the processed data directory
  file.path(project_root, "data", "processed", ...)
}

# Creating a function to build paths from the results data directory
results_path <- function(...) {
  
  # Combining the project root directory with the results data directory
  file.path(project_root, "data", "results", ...)
}

# Creating a function to build paths from the R scripts directory
scripts_path <- function(...) {
  
  # Combining the project root directory with the R scripts directory
  file.path(project_root, "scripts", ...)
}

# Creating a function to build paths from the report scripts directory
report_scripts_path <- function(...) {
  
  # Combining the project root directory with the report scripts directory
  file.path(project_root, "reports", "scripts", ...)
}

# Creating a helper to read a GeoParquet file back as an sf object.
# arrow::read_parquet returns the geometry as a geoarrow_vctr (not an sfc),
# so sf operations fail until it is converted. It also preserves the sf
# class and the "sf_column" attribute pointing to the original geometry
# column name, which collides if we rename the column afterwards. The
# helper strips the sf wrapper down to a plain tibble first, then converts
# and rebuilds the sf object with a standardised "geometry" column.
read_geoparquet_sf <- function(file) {
  layer <- as_tibble(read_parquet(file))
  geom_col <- names(layer)[vapply(layer, inherits, logical(1), "geoarrow_vctr")]
  layer[[geom_col]] <- st_as_sfc(layer[[geom_col]])
  if (geom_col != "geometry") {
    names(layer)[names(layer) == geom_col] <- "geometry"
  }
  st_as_sf(layer, sf_column_name = "geometry")
}


################################################################################
##### II. Project root
################################################################################

# Finding the project root directory
project_root <- find_project_root()


################################################################################
##### III. Required directories
################################################################################

# Creating the list of required data directories
required_directories <- c(
  data_path(),
  raw_path(),
  processed_path(),
  results_path()
)

# Creating the required directories
for (directory_path in required_directories) {
  
  # Creating the directory silently
  dir.create(
    path         = directory_path,
    recursive    = TRUE,
    showWarnings = FALSE
  )
}
