################################################################################
##################################            ##################################
############## 04.03) DOWNLOAD ITBI TRANSACTION DATA (2006-2025) ###############
##################################            ##################################
################################################################################

################################################################################
##### I. Packages
################################################################################

# # Installing packages
# install.packages("zip")

# Loading libraries
library(zip)


################################################################################
##### II. Directories and files
################################################################################

# Loading project paths
source(file.path("scripts", "_config", "paths.R"))

# Setting output data directory path
output_directory <- raw_path("floorspace_prices")

# Setting output ZIP archive path
output_zip <- file.path(output_directory, "itbi_guides.zip")

# Creating a temporary staging directory for the individual xlsx files
staging_directory <- tempfile(pattern = "itbi_guides_")
dir.create(
  path         = staging_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)


################################################################################
##### III. ITBI file URLs
################################################################################

# Setting source metadata page
itbi_source_page <- "https://prefeitura.sp.gov.br/web/fazenda/w/acesso_a_informacao/31501"

# Mapping each reference year (2006-2025) to its direct download URL (as each follows different naming conventions across periods, it's listed explicitly
itbi_urls <- c(
  "2025" = "https://prefeitura.sp.gov.br/cidade/secretarias/upload/fazenda/arquivos/itbi/GUIAS%20DE%20ITBI%20PAGAS%20%2828012026%29%20XLS.xlsx",
  "2024" = "https://prefeitura.sp.gov.br/cidade/secretarias/upload/fazenda/arquivos/itbi/GUIAS-DE-ITBI-PAGAS-2024.xlsx",
  "2023" = "https://www.prefeitura.sp.gov.br/cidade/secretarias/upload/fazenda/arquivos/XLSX/GUIAS-DE-ITBI-PAGAS-2023.xlsx",
  "2022" = "https://www.prefeitura.sp.gov.br/cidade/secretarias/upload/fazenda/arquivos/XLSX/GUIAS_DE_ITBI_PAGAS_12-2022.xlsx",
  "2021" = "https://www.prefeitura.sp.gov.br/cidade/secretarias/upload/fazenda/arquivos/itbi/ITBI_Setembro_2022/GUIAS_DE_ITBI_PAGAS_(2021).xlsx",
  "2020" = "https://www.prefeitura.sp.gov.br/cidade/secretarias/upload/fazenda/arquivos/itbi/ITBI_Setembro_2022/GUIAS_DE_ITBI_PAGAS_(2020).xlsx",
  "2019" = "https://www.prefeitura.sp.gov.br/cidade/secretarias/upload/fazenda/arquivos/itbi/ITBI_Setembro_2022/GUIAS_DE_ITBI_PAGAS_(2019).xlsx",
  "2018" = "https://www.prefeitura.sp.gov.br/cidade/secretarias/upload/fazenda/arquivos/itbi/guias_de_itbi_pagas_2018.xlsx",
  "2017" = "https://www.prefeitura.sp.gov.br/cidade/secretarias/upload/fazenda/arquivos/itbi/guias_de_itbi_pagas_2017.xlsx",
  "2016" = "https://www.prefeitura.sp.gov.br/cidade/secretarias/upload/fazenda/arquivos/itbi/guias_de_itbi_pagas_2016.xlsx",
  "2015" = "https://www.prefeitura.sp.gov.br/cidade/secretarias/upload/fazenda/arquivos/itbi/guias_de_itbi_pagas_2015.xlsx",
  "2014" = "https://www.prefeitura.sp.gov.br/cidade/secretarias/upload/fazenda/arquivos/itbi/guias_de_itbi_pagas_2014.xlsx",
  "2013" = "https://www.prefeitura.sp.gov.br/cidade/secretarias/upload/fazenda/arquivos/itbi/guias_de_itbi_pagas_2013.xlsx",
  "2012" = "https://www.prefeitura.sp.gov.br/cidade/secretarias/upload/fazenda/arquivos/itbi/guias_de_itbi_pagas_2012.xlsx",
  "2011" = "https://www.prefeitura.sp.gov.br/cidade/secretarias/upload/fazenda/arquivos/itbi/guias_de_itbi_pagas_2011.xlsx",
  "2010" = "https://www.prefeitura.sp.gov.br/cidade/secretarias/upload/fazenda/arquivos/itbi/guias_de_itbi_pagas_2010.xlsx",
  "2009" = "https://www.prefeitura.sp.gov.br/cidade/secretarias/upload/fazenda/arquivos/itbi/guias_de_itbi_pagas_2009.xlsx",
  "2008" = "https://www.prefeitura.sp.gov.br/cidade/secretarias/upload/fazenda/arquivos/itbi/guias_de_itbi_pagas_2008.xlsx",
  "2007" = "https://www.prefeitura.sp.gov.br/cidade/secretarias/upload/fazenda/arquivos/itbi/guias_de_itbi_pagas_2007.xlsx",
  "2006" = "https://www.prefeitura.sp.gov.br/cidade/secretarias/upload/fazenda/arquivos/itbi/guias_de_itbi_pagas_2006.xlsx"
)

# Building standardised staging file paths (itbi_guides_YYYY.xlsx)
itbi_staging_files <- file.path(
  staging_directory,
  paste0("itbi_guides_", names(itbi_urls), ".xlsx")
)

# Naming staging file vector to match years
names(itbi_staging_files) <- names(itbi_urls)


################################################################################
##### IV. Downloading data
################################################################################

# Extending R download timeout for large Excel files
options(timeout = 3600)

# Creating output directory
dir.create(
  path         = output_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Downloading one Excel file per reference year into the staging directory
for (year in names(itbi_urls)) {

  # Downloading ITBI Excel file
  message("Downloading ITBI guides: ", year, " ...")
  download.file(
    url      = itbi_urls[year],
    destfile = itbi_staging_files[year],
    method   = "libcurl",
    mode     = "wb",
    quiet    = FALSE,
    headers  = c("User-Agent" = "Mozilla/5.0")
  )
}


# Reporting downloaded files and their sizes
itbi_file_info <- data.frame(
  year      = names(itbi_staging_files),
  file      = basename(itbi_staging_files),
  size_mb   = round(file.info(itbi_staging_files)$size / 1024^2, 2),
  row.names = NULL
)

# Printing download summary
print(itbi_file_info)


################################################################################
##### V. Bundling files into a single ZIP archive
################################################################################

# Removing any previously bundled ZIP
if (file.exists(output_zip)) {
  file.remove(output_zip)
}

# Zipping all xlsx files into a single archive (entries stored by basename only,
# without the temp staging path), using the pure-R zip package
message("Bundling ITBI xlsx files into ", basename(output_zip), " ...")
zip::zipr(
  zipfile = output_zip,
  files   = itbi_staging_files,
  recurse = FALSE
)


# Removing the temporary staging directory (so only the ZIP remains on disk)
unlink(
  x         = staging_directory,
  recursive = TRUE,
  force     = TRUE
)

# Reporting final ZIP size
message(
  "ITBI guides bundled successfully. Archive size: ",
  round(file.info(output_zip)$size / 1024^2, 2), " MB."
)
