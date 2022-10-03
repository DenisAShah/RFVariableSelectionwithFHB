## Objective(s)
# * examine variable selection via the Boruta algorithm
# * use the Boruta-confirmed variables in a RF model
# 
# ---------------------------------------------------------------------------------------
# 
# Data files created in this script:
#  BorutaResSmall.RData
# ---------------------------------------------------------------------------------------
#
# 
## ----Libraries, eval=TRUE, echo=FALSE, message=FALSE--------------------------------------------------------
library(tidyverse)
library(tidymodels)
# themis is not part of tidymodels:
library(themis)
library(OptimalCutpoints)
library(viridis)

library(Boruta)
library(rFerns)

library(conflicted)

tidymodels_prefer()

conflict_prefer("col_factor", "readr")



## ----Load-and-Process-Data, echo=FALSE, eval=TRUE-----------------------------------------------------------
# Read the FHB dataset from the .csv file:
source("../ReadFHBDataset.R")

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




## ----Recipe-and-Prep, eval=TRUE, echo=FALSE-----------------------------------------------------------------
X2 <- 
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
# names(X2)

# Set up just the response and the predictors to feed into Boruta:
X3 <- 
  X2 %>% 
  dplyr::select(-c(id:S))



## ----Removed-Variables, eval=FALSE, echo=FALSE--------------------------------------------------------------
## # A closer look at the variables removed by the correlation filter
## 
## # Set up the filter:
## corr_filter <-
##   recipe(Y ~ ., data = X1 %>% select(-c(id:S))) %>%
##   step_corr(all_numeric_predictors(), threshold = 0.9)
## 
## filter_obj <- prep(corr_filter, training = X1 %>% select(-c(id:S)))
## 
## # And table out the removed variables:
## tidy(filter_obj, number = 1) %>%
##   arrange(terms) %>%
##   print(n = Inf)




### Resamples
## ----Resamples-Setup, eval=TRUE, echo=FALSE-----------------------------------------------------------------
set.seed(14092)
# NOTE: have to hardcode n for the number of bootstrap samples:
N_BOOT <- 25
folds <- nested_cv(X3, 
                   outside = vfold_cv(v = 10, repeats = 10, strata = Y), 
                   inside = bootstraps(times = N_BOOT, strata = Y))

# Have a look at the resampling object:
# folds
# folds %>% purrr::pluck("inner_resamples", 1)
# and the first of the bootstrap resamples:
# folds %>% purrr::pluck("inner_resamples", 1, "splits", 1)
# which is of class: rsplit
# folds %>% purrr::pluck("inner_resamples", 1, "splits", 1) %>% class()



## ----Resamples-for-Testing, eval=FALSE, echo=FALSE----------------------------------------------------------
## # A small set of resamples for testing that the algorithm works:
## set.seed(14092)
## # NOTE: have to hardcode n for the number of bootstrap samples:
## N_BOOT <- 5
## folds <- nested_cv(X3,
##                    outside = vfold_cv(v = 5, repeats = 1, strata = Y),
##                    inside = bootstraps(times = N_BOOT, strata = Y))



## ----Fitting-Functions, eval=TRUE, echo=FALSE---------------------------------------------------------------
get_model <- function(object) {
  # Fit a Boruta model and save the model object
  # Args:
  #  object = an `rsplit` object, in this case the bootstrap samples
  # Returns:
  #  A fitted Boruta object
  #  
  set.seed(14092)
  # We use variable importance through the rFerns package to speed things up:
  bar <- Boruta(Y ~ ., data = analysis(object), getImp = getImpFerns, maxRuns = 200, num.trees = 1000)
  return(bar)
  }


model_obj <- function(object) {
  # A wrapper to the `get_model` function. Needed because each inner_resample consists of N_BOOT bootstrap samples.
  # Args:
  #  object = an `rsplit` object in `folds$inner_resamples` 
  # Returns:
  #  Nothing. This is a wrapper to the `get_model` function
  purrr::map(object$splits, get_model)
}


get_confirmed <- function(object) {
  # A tibble of the confirmed variables from a Boruta model
  # Args:
  #  object = one of the rows of the Bormdl columns, which is itself a list containing the model fits to the bootstrap samples.
  # Returns:
  #  a tibble of the "confirmed" variables
  z <- as_tibble(object$finalDecision, rownames = "var") %>% dplyr::filter(value == "Confirmed") %>% dplyr::select(var)
  return(z)
}


confirmed_obj <- function(object) {
  # A wrapper to the `get_confirmed` function
  # Args:
  #  object = the Bormdl column
  # Returns:
  #  Nothing. This is a wrapper to `get_confirmed`
  purrr::map(object, get_confirmed)
}


get_fmla <- function(object) {
  #  Extract the confirmed formula from a Boruta model.
  # Args:
  #  object = one of the rows of the Bormdl columns
  # Returns:
  #  a formula object
  fmla <- getConfirmedFormula(object)
  return(fmla)
}


fmla_obj <- function(object) {
  # a wrapper to the `get_fmla` function
  # Args:
  #  object = the Bormdl column
  # Return:
  #  Nothing. This is a wrapper to `get_fmla`
  purrr::map(object, get_fmla)
}


# Model specification:
rf_spec <- rand_forest(trees = 1000) %>%
  set_mode("classification") %>%
  set_engine("ranger", seed = 55)


get_stats <- function(object, fmla) {
  # Return the ROC-AUC on the assessment part of the bootstrap resample
  # Args:
  #  object = an rsplit object from the inner_resamples column
  #  fmla = a model formula from the fmla column
  # Returns:
  #  the roc_auc for the prediction of the model on the assessment part of the bootstrap split, after being trained on the analysis part of the split
  #
  # Set up the workflow:
  rf_wf <- 
    workflow() %>%
    add_formula(fmla) %>%
    add_model(rf_spec) %>%
    # Fit the model on the analysis part of the rsplit object:
    fit(data = analysis(object))
  
  # Set up the predictions on the assessment part of the rsplit object:
  rf_pred <- 
    # Get the predicted probabilities:
    predict(rf_wf, assessment(object), type = "prob") %>% 
    # Add the true outcome data back in:
    dplyr::bind_cols(assessment(object) %>% select(Y))
  
  # Get the roc_auc:
  rf_pred %>%  
    roc_auc(truth = Y, .pred_Epi) %>%
    dplyr::select(.estimate)
}

stats_obj <- function(object, fmla) {
  # A wrapper to the `get_stats` function
  # Args:
  #  object = an `rsplit` object in `folds$inner_resamples` 
  # fmla = a model formula from the fmla column
  # Return:
  #  Nothing. This is a wrapper which calls `get_stats`
  purrr::map2(object$splits, fmla, get_stats)
}


get_confirmed_smry <- function(object) {
  # table the frequency at which variables were selected ("confirmed") across the inner_resamples bootstraps
  # Args:
  #  object = the confirmed column
  # Returns:
  #  a tibble of the Boruta confirmed variables and how often across the bootstrap resamples 
  z <- 
    purrr::map_df(object, bind_rows) %>%
    dplyr::count(var)
  return(z)
}



## ----Fit-and-Save-Models, eval=TRUE, echo=FALSE-------------------------------------------------------------
## What you want to do:
# For each inner_resamples bootstraps:
# 1. Run Boruta on the analysis part of the bootstrap sample
# 2. Save a tibble of the "confirmed" variables
# 3. Extract the "confirmed" formula and fit a RF on the analysis part of the bootstrap sample
# 4. Predict on the assessment part of the bootstrap sample
# This will give you estimates of RF model performance using the set of variables "confirmed" by Boruta

# For each of the outer resamples:
# 1. tabulate the frequency (proportion) at which a variable was selected across the bootstrap samples (confirmed column)
# 2. Create a model formula from the set of variables that were confirmed in each bootstrap sample. Restricted to variables that were confirmed in ALL of the bootstrap samples (N_BOOT)
# 3. Use the formula to fit a RF to the analysis part of splits, and predict on the assessment part. Use the default RF settings, no tuning.
# 4. Repeat the whole process to get an estimate of the outer cv auc variability (by setting the repeats argument in the nested_cv function)

start <- Sys.time()
# Add the fitted Boruta model to the resampled data object:
Boruta_res <-
  folds %>%
  dplyr::mutate(Bormdl = purrr::map(inner_resamples, model_obj)) %>%
  # Add a column for the confirmed variables (each row item is a list, corresponding to the number of bootstrap samples):
  dplyr::mutate(confirmed = purrr::map(Bormdl, confirmed_obj)) %>%
  # Add a column for the formula based on the confirmed variables:
  dplyr::mutate(fmla = purrr::map(Bormdl, fmla_obj)) %>%
  # Add a column for the roc_auc estimated on the assessment part of the bootstrap samples, after training a RF to the "confirmed" set of variables on the analysis part of the split:
  dplyr::mutate(auc = purrr::map2(inner_resamples, fmla, stats_obj)) %>%
  # Add a column for the summary of the confirmed variables across the bootstrap resamples:
  dplyr::mutate(confirmed_smry = purrr::map(confirmed, get_confirmed_smry)) %>%
  # Create a model formula from the set of variables that were confirmed in each bootstrap sample. Restricted to variables that were confirmed in ALL of the bootstrap samples (N_BOOT):
  dplyr::mutate(fmla2 = purrr::map(confirmed_smry, function(.confirmed_smry) {zee <- .confirmed_smry %>% dplyr::filter(n == N_BOOT) %>% dplyr::pull(var); return(paste("Y ~", paste(zee, collapse = " + ")) %>% as.formula(.)) })) %>%
  # Use the formula to fit a RF to the analysis part of splits, and predict on the assessment part. Use the default RF settings, no tuning.
  dplyr::mutate(auc2 = purrr::map2(splits, fmla2, get_stats)) %>%
  # saving the object at this point will result in a 6.5 GB file!!! So process this file down to what you need.
  dplyr::select(splits, id, confirmed_smry, auc2)

end <- Sys.time()
difftime(end, start, units = "mins")  # Took 221 min (3.7 hr)

# save(Boruta_res, file = "BorutaResSmall.RData")





# # Computational environment
## ----SessionInfo, eval=TRUE, echo=FALSE, results='markup'---------------------------------------------------
R.Version()$version.string
R.Version()$system
sessionInfo()

