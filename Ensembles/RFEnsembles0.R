#' <!-- Run on R 4.1.3 -->
#' 
#' ---------------------------------------------------------------------------------------
#'  Data files created by this script:
#'    StackedMetrics.RData
#' ---------------------------------------------------------------------------------------
#' 
#' # Objective(s)
#' * have a set of tuned RF models after using the varSelRF algorithm
#' * also have another set of tuned RF models after using the VSURF algorithm
#' * taking these two sets together, can we ensemble them?
#' 
#' 
#' ---------------------------------------------------------------------------------------
#' 
#' 
## ----Libraries--------------------------------------------------------------------------
library(tidyverse)
library(tidymodels)
library(stacks)
library(ranger)

library(OptimalCutpoints)
library(PRROC)

library(kableExtra)

tidymodels_prefer()

#' 
#' 
#' # Stacking
#' * Objective: stack the RF models suggested from varSelRF (20 models) and VSURF (38 models). That is, we attempt to stack from a set of 58 RF models.
#' 
#' <!-- Data setup and partition -->
## ----data-setup-------------------------------------------------------------------------
## The set of variables used by the varSelRF models:
# Load the object (m1) containing the information on the models:
# (assumes you have run the script `varSelRF0.Rmd` in the varSelRF folder and have saved this RData file)
load("../varSelRF/varSelRFResII.RData")

# Get the variables (as used across the 20 varSelRF models):
varSelRF.vars <- 
  m1 %>%
  dplyr::select(max.vars, max.no.vars, max.fmla, auc.outer) %>%
  tidyr::unnest(cols = auc.outer) %>%
  tibble::rownames_to_column() %>%
  # the 20 models:
  dplyr::filter(.estimate >= 0.92, max.no.vars >= 9, max.no.vars <= 14) %>%
  rename(vars = max.vars, no.vars = max.no.vars, fmla = max.fmla, auc = .estimate) %>%  
  dplyr::select(vars) %>%
  tidyr::unnest(cols = vars) %>%
  dplyr::distinct() %>%
  dplyr::pull(var)


## The variables used across the set of VSURF models:
# Load the saved object with the VSURF results:
# (assumes the script `VSURF0.Rmd` in the VSURF folder was run and this RData file was saved)
load("../VSURF/VSURF0Res.RData")

# the id's of duplicated models:
dups <-
  vsurf %>%
  tibble::rowid_to_column() %>%
  dplyr::select(rowid, indx) %>%
  # Sort the indices:
  dplyr::mutate(sorted = map(indx, sort)) %>%
  # The filtering step identifies the duplicates:
  dplyr::group_by(sorted) %>%
  dplyr::filter(n() > 1) %>%
  # Arrange so that the duplicates are shown together:
  dplyr::arrange(sorted) %>%
  # and filter out every other:
  dplyr::filter(row_number() %% 2 == 1) %>%
  # the rowid's of the duplicates to remove:
  dplyr::pull(rowid)

# Now we filter to a subset of models to pursue further.
# Distinct, 6-9 vars, auc no less than 0.8
vsurf.filtered <-
  vsurf %>%
  tibble::rowid_to_column() %>%
  dplyr::mutate(no_vars = purrr::map(indx, length)) %>%
  dplyr::mutate(vars = map2(splits, indx, function(.splits, .indx) {
    x <- analysis(.splits) %>% select(-Y)
    names(x)[.indx]})) %>%
  dplyr::select(rowid, no_vars, auc, vars) %>%
  tidyr::unnest(cols = c(no_vars, auc)) %>%
  # just easier to call the column auc:
  dplyr::rename(auc = .estimate) %>%
  # apply our filtering criteria:
  dplyr::filter(!rowid %in% dups, no_vars %in% 6:9, auc > 0.8) 

vsurf.vars <-
  vsurf.filtered %>%
  dplyr::select(vars) %>%
  tidyr::unnest(cols = vars) %>%
  dplyr::distinct() %>%
  dplyr::pull()

# The set of vars across both sets of models (varSelRF and VSURF). There are 35 in all:
vars_sub <-
  c(varSelRF.vars, vsurf.vars) %>%
  unique()


# Load the fhb data matrix:
# (Make sure your path is correctly specified)
source("../ReadFHBDataset.R")

# Some cleanup (removal of objects not needed at this point):
rm(list = ls()[!(ls() %in% c("X", "vars_sub"))]) 

# The response and set of predictors needed to fit the different RF models:
fhb <-
  X %>%
  # Set up Y as a factor (tidymodels):
  dplyr::mutate(Y = ifelse(S < 10, "Nonepi", "Epi")) %>%
  # The first level is the one you want to predict:
  dplyr::mutate(Y = factor(Y, levels = c("Epi", "Nonepi"))) %>%
  dplyr::select(Y, all_of(vars_sub))


# Set up the data partition:
set.seed(2331)
fhb_split <- initial_split(fhb, prop = 2/3, strata = Y)
fhb_train <- training(fhb_split)
fhb_test  <- testing(fhb_split)

# Cross-validation folds:
set.seed(648)
fhb_folds <- vfold_cv(fhb_train, strata = Y, v = 5)

eval_tuned_bayes <- function(.x, .mdl) {
  # Extract the parameters for the best fit to a model, fit the training data cv folds with these tuned parameters, and obtain the predicted probabilities of an epidemic on the held out partition of the fold.
  # Args:
  #  .x = a workflowset object holding the tuning results
  #  .mdl = character string for the model, e.g. "M1"
  # Returns:
  #  a tibble with columns for the model, Y and predicted probs on the held-out cv fold
  #
  # The tuned parameters resulting in the best fit for the model:
  best_results <-
    .x %>%
    extract_workflow_set_result(.mdl) %>%
    select_best()
  
  # Extract model, fit to the training set with the tuned parameters, and evaluate on the test set:
  set.seed(1001)     # set seed for reproducibility. RF uses bootstrap sampling in building trees
  
  # For stacking we need to save the predictions and workflow:
  keep_pred <- control_resamples(save_pred = TRUE, save_workflow = TRUE)
  
  .x %>% 
    extract_workflow(.mdl) %>%           # return the workflow for model
    finalize_workflow(best_results) %>%  # update the model with the tuning parameters
    fit_resamples(resamples = fhb_folds, control = keep_pred)  # fit the updated model
  }  # end function eval_tuned_bayes

#' 
#' 
#' <!-- Set up the data stack object -->
## ----stack-setup------------------------------------------------------------------------
# Using the Bayes tuning results for the varSelRF models:
# (Again, assumes this .rds file has been saved after running `varSelRF1.R` in the varSelRF folder)
varselrf_mods <- readRDS("../varSelRF/varSelRF1ResBayes.rds")

# Set the names of the model list:
num_mods <- 1:20
mdl <- stringr::str_c("M", num_mods)

# A list to store the varSelRF models after processing with the eval_tuned_bayes function:
varselrf_list <- vector(mode = "list", length = length(num_mods))

# Populate the list:
for (i in num_mods) {
  varselrf_list[[i]] <- eval_tuned_bayes(.x = varselrf_mods, .mdl = mdl[i])
}

# Initiate the stacking object:
fhb_st <- stacks()

# And add the varSelRF models to it:
for (i in num_mods) {
  fhb_st <- 
    fhb_st %>% 
    add_candidates(varselrf_list[[i]], name = str_c("varselrf_", mdl[i]))
}

# Don't need the large varselrf_mods object anymore:
rm(varselrf_mods)


# Now we get the tuned VSURF models:
# (Assuming the .rds file was saved after running `VSURF1.R` in the VSURF folder)
vsurf_mods <- readRDS("../VSURF/VSURF1.rds")

# Set the names of the model list:
num_mods <- 1:38
mdl <- stringr::str_c("M", num_mods)

# A list to store the varSelRF models after processing with the eval_tuned_bayes function:
vsurf_list <- vector(mode = "list", length = length(num_mods))

# Populate the list:
for (i in num_mods) {
  vsurf_list[[i]] <- eval_tuned_bayes(.x = vsurf_mods, .mdl = mdl[i])
}

# And add the VSURF models to the stack:
for (i in num_mods) {
  fhb_st <- 
    fhb_st %>% 
    add_candidates(vsurf_list[[i]], name = str_c("vsurf_", mdl[i]))
}

# Now we are all set up for ensembling on the model stack...
rm(list = ls()[!(ls() %in% c(str_subset(ls(), "^fhb")))]) 

#' 
#' 
## ----stack-fit-then-predict-to-test-data--------------------------------------------------------------------
# Once you have the model stack, determine how to combine their predictions
# 1. lasso
set.seed(2331)
fhb_st.lasso <- 
  fhb_st %>%
  blend_predictions() %>%
  # fit the candidates with nonzero stacking coefficients
  fit_members()

# Out of 58 possible members, the ensemble retained six.  One from varSelRF and the others from VSURF
# varSelRF M19, vsurf M8, M10, M11, M20, M21
fhb_st.lasso
autoplot(fhb_st.lasso, type = "weights")


# 2. ridge
set.seed(2331)
fhb_st.ridge <- 
  fhb_st %>%
  blend_predictions(mixture = 0) %>%
  # fit the candidates with nonzero stacking coefficients
  fit_members()

# Out of 58 possible candidate members, the ensemble retained 11
# varselRF M19, vsurf M8, M9, M10, M11, M13, M14, M15, M20, M21, M32
fhb_st.ridge$member_fits %>% names()
autoplot(fhb_st.ridge, type = "weights")

# 3. Elastic-net
set.seed(2331)
fhb_st.en <- 
  fhb_st %>%
  blend_predictions(mixture = 0.5) %>%
  # fit the candidates with nonzero stacking coefficients
  fit_members()

# Out of 58 possible candidate members, the ensemble retained 9:
# varselRF M19, vsurf M8, M9, M10, M11, M13, M14, M20, M21
fhb_st.en$member_fits %>% names()


# At this point, ready for prediction on the test data:
lasso_pred <-
  fhb_test %>%
  bind_cols(predict(fhb_st.lasso, ., type = "prob"))

ridge_pred <-
  fhb_test %>%
  bind_cols(predict(fhb_st.ridge, ., type = "prob"))

en_pred <-
  fhb_test %>%
  bind_cols(predict(fhb_st.en, ., type = "prob"))

#' 
#' 
#' * We used lasso, ridge or elasticnet regression as the meta-learner.  
#' 
#' * Out of the 58 RF models, lasso retained 6 RF models, ridge retained 11, and elasticnet 9. Only 1 varSelRF model was retained (M19) by all three meta-learners.  The VSURF models retained varied among the meta-learners, but overall the following 10 VSURF models were retained: M8, M9, M10, M11, M13, M14, M15, M20, M21, M32. 
#' 
#' * That is, even though the meta-learner was fed all 58 RF models, it set the coefs for many of them to zero. The meta-learner was then trained only with the retained RF models, and the fit meta-learner used to predict on the test data.
#' 
#' 
#' <!-- Calculate performance metrics -->
## ----performance-metrics-function---------------------------------------------------------------------------
CalculateStats <- function(.x) {
  # calculate the statistics from the predicted probs for each model:
  # Args:
  #  .x = a nested object containing predicted probs for each model (e.g. grid_nested)
  # Returns:
  #  a tibble of estimated metrics
  #
  .x %>%
    # number of rows:
    dplyr::mutate(n = purrr::map_dbl(data, ~nrow(.x))) %>%
    # data frame of the actual values and predicted probs for input into OptimalCutpoints:
    dplyr::mutate(df = purrr::map(data, ~{data.frame(id = 1:nrow(.x), actual = .x$y, prob = .x$prob)})) %>%
    # get the cutpoint based on Youden:
    dplyr::mutate(oc = purrr::map(df, ~OptimalCutpoints::optimal.cutpoints(X = prob ~ actual, tag.healthy = 0, methods = "Youden", data = .x))) %>%
    dplyr::mutate(cp.val = purrr::map_dbl(oc, ~pluck(.x, "Youden", 1, "optimal.cutoff", "cutoff", 1))) %>%
    # The actual class:
    dplyr::mutate(actual = purrr::map(data, "y")) %>%
    # The predicted class:
    dplyr::mutate(pred = purrr::map2(data, cp.val, .f = function(.data, .cp) {z = as.data.frame(.data) %>%
      dplyr::pull(prob); ifelse(z <= .cp, 0, 1)})) %>%
    # Set actual and pred as factors (required for `yardstick`):
    dplyr::mutate(actual.f = purrr::map(actual, ~factor(.x, levels = c(1, 0)))) %>%
    dplyr::mutate(pred.f = purrr::map(pred, ~factor(.x, levels = c(1, 0)))) %>%
    dplyr::mutate(data.f = purrr::map2(actual.f, pred.f, ~{data.frame(truth = .x, estimate = .y)})) %>%
    # ROC_AUC:
    dplyr::mutate(auc = purrr::map_dbl(data, ~{yardstick::roc_auc(.x, truth = Y, prob, options = list(smooth = TRUE)) %>%
        dplyr::pull(.estimate)})) %>%
    # precision-recall area under curve:
    dplyr::mutate(prauc = purrr::map_dbl(data, ~{PRROC::pr.curve(scores.class0 = .x$prob, weights.class0 = .x$y) %>% purrr::pluck("auc.integral")})) %>%
    
    # F-Measure:
    dplyr::mutate(F1 = purrr::map_dbl(data.f, ~{yardstick::f_meas(.x, truth = truth, estimate = estimate) %>%
        dplyr::pull(.estimate)})) %>%
    # Kappa:
    dplyr::mutate(kap = purrr::map_dbl(data.f, ~{yardstick::kap(.x, truth = truth, estimate = estimate) %>%
        dplyr::pull(.estimate)})) %>%
    # Detection prevalence:
    dplyr::mutate(dp = purrr::map_dbl(data.f, ~{yardstick::detection_prevalence(.x, truth = truth, estimate = estimate) %>%
        dplyr::pull(.estimate)})) %>%
    # mcc:
    dplyr::mutate(mcc = purrr::map_dbl(data.f, ~{yardstick::mcc(.x, truth = truth, estimate = estimate) %>%
        dplyr::pull(.estimate)})) %>%
    # Brier score:
    dplyr::mutate(Brier = map_dbl(data, ~sum((.x$prob - .x$y)^2)/nrow(.x))) %>%
    
    # true positives count:
    dplyr::mutate(TP = purrr::map2_dbl(actual, pred, ~{sum(.x == 1 & .y == 1)})) %>%
    # false positives count:
    dplyr::mutate(FP = purrr::map2_dbl(actual, pred, ~{sum(.x == 0 & .y == 1)})) %>%
    # false negatives count:
    dplyr::mutate(FN = purrr::map2_dbl(actual, pred, ~{sum(.x == 1 & .y == 0)})) %>%
    # true negatives count:
    dplyr::mutate(TN = purrr::map2_dbl(actual, pred, ~{sum(.x == 0 & .y == 0)})) %>%
    # All negatives:
    dplyr::mutate(AN = purrr::map2_dbl(TN, FP, ~{.x + .y})) %>%
    # All positives:
    dplyr::mutate(AP = purrr::map2_dbl(TP, FN, ~{.x + .y})) %>%
    
    # Misclassification rate:
    dplyr::mutate(mr = purrr::pmap_dbl(list(FP, FN, n), ~{(..1 + ..2)/..3})) %>%
    # Accuracy:
    dplyr::mutate(acc = purrr::map_dbl(mr, ~{1 - .x})) %>%
    # No information rate:
    dplyr::mutate(nir = purrr::pmap_dbl(list(TN, FP, n), ~{(..1 + ..2)/..3})) %>%
    
    # sensitivity:
    dplyr::mutate(Se = purrr::map2_dbl(TP, FN, ~{.x/(.x + .y)})) %>%
    # specificity:
    dplyr::mutate(Sp = purrr::map2_dbl(TN, FP, ~{.x/(.x + .y)})) %>%
    # YI/ifd/K:
    dplyr::mutate(ifd = purrr::map2_dbl(Se, Sp, ~{.x + .y - 1})) %>%
    # G-Mean:
    dplyr::mutate(GM = purrr::map2_dbl(Se, Sp, ~{sqrt(.x*.y)})) %>%
    # The average of Se and Sp (balanced accuracy):
    dplyr::mutate(bac = purrr::map2_dbl(Se, Sp, ~{(.x + .y)/2})) %>%
    # Power metric (PM; Lopes et al. 2017):
    dplyr::mutate(PM = purrr::map2_dbl(Se, Sp, ~{.x/(1 + .x - .y)})) %>%
    # discriminant power:
    dplyr::mutate(dpow = purrr::map2_dbl(Se, Sp, ~{(sqrt(3)/pi)*(log(.x/(1-.x)) + log(.y/(1-.y)))})) %>%
    # Positive diagnostic likelihood ratio:
    dplyr::mutate(DLR.pos = purrr::map2_dbl(Se, Sp, ~{.x/(1 - .y)})) %>%
    # Negative diagnostic likelihood ratio:
    dplyr::mutate(DLR.neg = purrr::map2_dbl(Se, Sp, ~{(1 - .x)/.y})) %>%
    # Diagnostic odds ratio (DOR):
    dplyr::mutate(DOR = purrr::map2_dbl(DLR.pos, DLR.neg, ~{.x/.y})) %>%
    # Prevalence threshold (PT):
    dplyr::mutate(PT = purrr::map2_dbl(Se, Sp, ~{(-1 + .y + sqrt(.x - .y*.x))/(-1 + .y + .x)})) %>%
    # positive predictive value (ppv) = Pr(D1|T1) = precision:
    dplyr::mutate(ppv = purrr::map2_dbl(TP, FP, ~{.x/(.x + .y)})) %>%
    # negative predictive value (npv) = Pr(D0|T0):
    dplyr::mutate(npv = purrr::map2_dbl(TN, FN, ~{.x/(.y + .x)})) %>%
    # markedness aka Powers (2011):
    dplyr::mutate(mkd = purrr::map2_dbl(ppv, npv, ~{.x + .y - 1})) %>%
    # Fowlkes–Mallows index:
    dplyr::mutate(FM = purrr::map2_dbl(ppv, Se, ~{sqrt(.x*.y)})) %>%
    
    # The normalized prediction-realization table (next 4 lines):
    dplyr::mutate(TPn = purrr::pmap_dbl(list(actual, pred, n), ~{sum(..1 == 1 & ..2 == 1)/..3})) %>%
    dplyr::mutate(FPn = purrr::pmap_dbl(list(actual, pred, n), ~{sum(..1 == 0 & ..2 == 1)/..3})) %>%
    dplyr::mutate(FNn = purrr::pmap_dbl(list(actual, pred, n), ~{sum(..1 == 1 & ..2 == 0)/..3})) %>%
    dplyr::mutate(TNn = purrr::pmap_dbl(list(actual, pred, n), ~{sum(..1 == 0 & ..2 == 0)/..3})) %>%
    
    # Prior probability of epidemic:
    dplyr::mutate(PrD1 = purrr::map2_dbl(TPn, FNn, ~{.x + .y})) %>%
    # Prior probability of non-epidemic:
    dplyr::mutate(PrD0 = purrr::map_dbl(PrD1, ~{1 - .x})) %>%
    # Probability of an epidemic prediction:
    dplyr::mutate(PrT1 = purrr::map2_dbl(TPn, FPn, ~{.x + .y})) %>%
    # Probability of a non-epidemic prediction:
    dplyr::mutate(PrT0 = purrr::map2_dbl(FNn, TNn, ~{.x + .y})) %>%
    # Information quantity (entropy) H(D):
    dplyr::mutate(HD = purrr::map2_dbl(PrD1, PrD0, ~{-(.x*log(.x) + .y*log(.y))})) %>%
    # Information quantity (entropy) H(T):
    dplyr::mutate(HT = purrr::map2_dbl(PrT1, PrT0, ~{-(.x*log(.x) + .y*log(.y))})) %>%
    # Information quantity (joint entropy) H(D,T):
    dplyr::mutate(HDT = purrr::pmap_dbl(list(TPn, FPn, FNn, TNn), ~{-(..1*log(..1) + ..2*log(..2) + ..3*log(..3) + ..4*log(..4))})) %>%
    # Expected mutual information (I_M(D,T)):
    dplyr::mutate(IM = purrr::pmap_dbl(list(HD, HT, HDT), ~{..1 + ..2 - ..3})) %>%
    # Conditional entropy H(D|T):
    dplyr::mutate(HDcT = purrr::map2_dbl(HD, IM, ~{.x - .y})) %>%
    # Normalized expected mutual information, (equiv. to McFadden's R2) Hughes et al. (2019):
    dplyr::mutate(IMN = purrr::map2_dbl(IM, HD, ~{.x/.y})) %>%
    
    # NMI measure of Forbes (1995) writing out this way because had problems with the ~ and ..1 notation
    # Also, using log2 instead of log -- seems better numerical accuracy. Same result.
    dplyr::mutate(NMI = purrr::pmap_dbl(list(TP, FP, FN, TN, n), function(.TP, .FP, .FN, .TN, .n) {1 - (-.TP*log2(.TP) - .FP*log2(.FP) - .FN*log2(.FN) - .TN*log2(.TN) + (.TP+.FP)*log2(.TP+.FP) + (.FN+.TN)*log2(.FN+.TN))/(.n*log2(.n) - ((.TP+.FN)*log2(.TP+.FN) + (.FP+.TN)*log2(.FP+.TN)))})) %>%
    
    # MCEN:
    dplyr::mutate(S = purrr::pmap_dbl(list(TP, FP, FN, TN), ~{..1 + ..2 + ..3 + ..4})) %>%
    dplyr::mutate(MCEN = purrr::pmap_dbl(list(S, TP, TN, FP, FN), ~{(2*(..5+..4)*log2((..1-..3)*(..1-..2)))/(3*..1 + ..5+..4) - (4*(..5*log2(..5) + ..4*log2(..4)))/(3*..1 + ..5 +..4)})) %>%
    # The inverse of MCEN:
    dplyr::mutate(imcen = purrr::map_dbl(MCEN, ~{1/.x})) %>%
    
    # Keep only the columns you need:
    dplyr::select(model, cp.val, auc:Brier, mr:FM, IMN, NMI, MCEN, imcen) %>%
    
    tidyr::unnest(cols = where(is.double)) %>%
    dplyr::ungroup()
  }  # end function CalculateStats

#' 
#' 
## ----stack-performance-metrics------------------------------------------------------------------------------
# Don't want to have to rewrite a lot of code.  The CalculateStats function which we have used previously with models from varSelRF and VSURF works on a nested object. Therefore, we'll create nested objects (albeit containing just one stacked model each) to pass to CalculateStats.

lasso_nested <- 
  lasso_pred %>%
  dplyr::select(Y, .pred_Epi) %>%
  dplyr::rename(prob = .pred_Epi) %>%
  # actual observation as a numeric (Y is a factor for yardstick functions):
  dplyr::mutate(y = ifelse(Y == "Nonepi", 0, 1), .before = "prob") %>%
  dplyr::mutate(model = "Ens_lasso", .before = "Y") %>%
  dplyr::group_by(model) %>%
  tidyr::nest()

ridge_nested <- 
  ridge_pred %>%
  dplyr::select(Y, .pred_Epi) %>%
  dplyr::rename(prob = .pred_Epi) %>%
  # actual observation as a numeric (Y is a factor for yardstick functions):
  dplyr::mutate(y = ifelse(Y == "Nonepi", 0, 1), .before = "prob") %>%
  dplyr::mutate(model = "Ens_ridge", .before = "Y") %>%
  dplyr::group_by(model) %>%
  tidyr::nest()

en_nested <- 
  en_pred %>%
  dplyr::select(Y, .pred_Epi) %>%
  dplyr::rename(prob = .pred_Epi) %>%
  # actual observation as a numeric (Y is a factor for yardstick functions):
  dplyr::mutate(y = ifelse(Y == "Nonepi", 0, 1), .before = "prob") %>%
  dplyr::mutate(model = "Ens_elasticnet", .before = "Y") %>%
  dplyr::group_by(model) %>%
  tidyr::nest()


# Get the performance metrics for each of the nested objects:
stack_lasso_metrics <- CalculateStats(lasso_nested)
stack_ridge_metrics <- CalculateStats(ridge_nested)
stack_en_metrics <- CalculateStats(en_nested)

# Just some checks:
stack_lasso_metrics$auc
stack_ridge_metrics$auc
stack_en_metrics$auc

#' 
#' 
#' 
## ----save-stack-metrics-----------------------------------------------------------------
# Save the metrics objects so that we don't have to rerun the steps:
save(stack_lasso_metrics, stack_ridge_metrics, stack_en_metrics, file = "StackedMetrics.RData")

#' 
#' 
#' 
#' # Computational environment
## ----SessionInfo------------------------------------------------------------------------
R.Version()$version.string
R.Version()$system
sessionInfo()

