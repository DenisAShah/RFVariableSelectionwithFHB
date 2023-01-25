# # Objective(s)
# * examine the variables before and after pre-screening
# 
# ---------------------------------------------------------------------------------------
# 
# 
## ----Libraries, eval=TRUE, echo=FALSE, message=FALSE------------------------------------------------------
library(tidyverse)
library(tidymodels)

library(kableExtra)

tidymodels_prefer()

# 
# 
## ----Load-the-Data, echo=FALSE, eval=TRUE-----------------------------------------------------------------
# Load the fhb data matrix:
# NOTE: set the proper paths for your system:
source("../ReadFHBDataset.R")

# 
# 
## ----Some-Processing-Steps--------------------------------------------------------------------------------
# Some pre-processing:
X1 <- 
  X %>%
  # Set up Y as a factor (tidymodels):
  dplyr::mutate(Y = ifelse(S < 10, "Nonepi", "Epi")) %>%
  # The first level is the one you want to predict:
  dplyr::mutate(Y = factor(Y, levels = c("Epi", "Nonepi"))) %>%
  dplyr::mutate(sq.T.A.PRE7.24H = T.A.PRE7.24H^2) %>%
  # add region as a variable:
  dplyr::left_join(tibble(state = state.abb, region = state.region), by = "state") %>%
  # Set up for the wc variable as in Shah et al. (2013)
  dplyr::mutate(wc = "NA") %>%
  dplyr::mutate(wc = replace(wc, type == "spring", "sw")) %>%
  dplyr::mutate(wc = replace(wc, type == "winter" & corn == 0, "wwnoc")) %>%
  dplyr::mutate(wc = replace(wc, type == "winter" & corn == 1, "wwc")) %>%
  dplyr::mutate(wc = factor(wc, levels = c("sw", "wwnoc", "wwc"))) %>%
  # Arrange variables:
  dplyr::select(id:type, region, corn, S, Y, resist, wc, T.A.1:sq.T.A.PRE7.24H)


# Keeping only weather-based variables (329):
X2 <- 
  X %>%
  dplyr::select(T.A.1:TRH.15T30nRHG90.POST15.24H)

# 
# 
## ----Recipe-and-Prep, eval=TRUE, echo=FALSE---------------------------------------------------------------
X3 <- 
  recipe(Y ~ ., data = X1) %>%
  update_role(c(id:S), new_role = "ID") %>%
  # remove any zero variance predictors:
  step_zv(all_predictors()) %>% 
  # remove any linear combinations:
  step_lincomb(all_numeric_predictors()) %>%
  # remove highly correlated variables:
  step_corr(all_numeric_predictors(), threshold = 0.9) %>%
  prep() %>%
  juice()
  
# Check that looks good:
# names(X3)

# Just the weather-based predictors (88):
X4 <- 
  X3 %>% 
  dplyr::select(-c(id:wc, Y))

# Check:
names(X4)

# 
# 
# 
## ----Metadata-prep----------------------------------------------------------------------------------------
# The variables metadata:
io <- readr::read_csv("../Data/VariableMetaData.csv", show_col_types = FALSE) %>%
  # convert character columns to factor (EXCEPT variable_name):
  dplyr::mutate(across(where(is.character) & !variable_name, factor)) %>%
  dplyr::mutate(period = factor(period, levels = c("pre", "post", "pre-post")))

# 
# 
## ----Full-variable-set-metadata---------------------------------------------------------------------------
# The meta-data associated with the full set of weather variables: 
io %>%
  dplyr::count(type) %>%
  dplyr::mutate(pct = 100*n/sum(n)) %>%
  kable(., row.names = TRUE, col.names = c("Type", "Count", "Percent")) %>%
  kable_styling(latex_options = c("striped"), position = "left", font_size = 11, full_width = FALSE)

# 
# 
## ----Screened-variable-set-metadata-----------------------------------------------------------------------
# The meta-data associated with the set of weather variables after pre-screening: 
io.s <-
   io %>% 
   dplyr::filter(variable_name %in% names(X4))


io.s %>%
  dplyr::count(type) %>%
  dplyr::mutate(pct = 100*n/sum(n)) %>%
  kable(., row.names = TRUE, col.names = c("Type", "Count", "Percent")) %>%
  kable_styling(latex_options = c("striped"), position = "left", font_size = 11, full_width = FALSE)

# 
# 
## ----Variable-types-pre-and-post-screening----------------------------------------------------------------
# Create a tibble showing the percent by variable type for the set of variables before screening and after screening

#  Full set:
full_set <-
  io %>%
  dplyr::count(type) %>%
  dplyr::mutate(pct_full = 100*n/sum(n)) %>%
  dplyr::select(type, pct_full)

# After pre-screening:
screened_set <-
  io.s %>%
  dplyr::count(type) %>%
  dplyr::mutate(pct_screened = 100*n/sum(n)) %>%
  dplyr::select(type, pct_screened)

# Join them up:
dplyr::left_join(full_set, screened_set, by = "type") %>%
  kable(., row.names = TRUE, col.names = c("Type", "Percent (full)", "Percent (screened")) %>%
  kable_styling(latex_options = c("striped"), position = "left", font_size = 11, full_width = FALSE)

# 
# 
## ----Stability-type-variables-----------------------------------------------------------------------------
# I also suspect stability-type variables (SD) were created later and were not present up to the 2013 paper.

io %>%
  dplyr::filter(str_detect(variable_name, "SD")) %>%
  dplyr::count(source)

# 
# 
# 
# # Computational environment
## ----SessionInfo, eval=TRUE, echo=FALSE, results='markup'-------------------------------------------------
R.Version()$version.string  # 4.1.3
R.Version()$system
sessionInfo()

