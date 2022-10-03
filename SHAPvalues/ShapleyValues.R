# OBJECTIVE
# Shapley explanations plot for VSURF_M21

# Data files created by this script:
#  shap.RData

# Steps:
# Get the tuned hyperparameters for VSURF_M21
# Divide the FHB dataset into train and test sets
# Fit the tuned model (using ranger) to the train set
# Use the tuned model to get the shap values on the test set


## Libraries used in the SETUP section
# library(tidyverse)
# library(tidymodels)
# library(ranger)
# library(fastshap)


################## SETUP ##################
# The Bayes tuning results:
# (Assumes the rds file has been created upon running the scripts in the VSURF folder)
b_res <- readRDS("../VSURF/VSURF1.rds")


# The tuned parameters resulting in the best fit for the model:
best_results <-
  b_res %>%
  extract_workflow_set_result("M21") %>%
  select_best()

best_results$mtry
best_results$min_n

rm(b_res)


# Load the saved object with the VSURF results:
# (assuming the RData object was created upon running the scripts in the VSURF folder)
load("../VSURF/VSURF0Res.RData")

# This gets the rowid's of duplicate models in the vsurf object:
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

# A list of the RF model formulas:
M21_vars <-
  vsurf.filtered %>%
  dplyr::slice(21) %>%
  dplyr::select(vars) %>%
  tidyr::unnest(cols = vars) %>%
  dplyr::pull(vars) %>%
  sort()
 

# Load the fhb data matrix:
source("../ReadFHBDataset.R")

# The response and set of predictors needed to fit the RF model:
fhb <-
  X %>%
  # Set up Y as a factor (tidymodels):
  dplyr::mutate(Y = ifelse(S < 10, 0, 1)) %>%
  # The first level is Nonepi:
  dplyr::mutate(Y = factor(Y)) %>%
  dplyr::select(Y, all_of(M21_vars))

str(fhb)


# Set up the data partition:
set.seed(2331)
fhb_split <- initial_split(fhb, prop = 2/3, strata = Y)
fhb_train <- training(fhb_split)
fhb_test  <- testing(fhb_split)

# Fit the tuned random forest
set.seed(1046)  # for reproducibility
rfo <- ranger(Y ~ ., data = fhb_train, num.trees = 1000, mtry = 1, min.node.size = 2, probability = TRUE)

# Prediction wrapper for `fastshap::explain()`; has to return a single (atomic) vector of predictions
pfun <- function(object, newdata) {  # computes prob(Y=1|x)
  predict(object, data = newdata)$predictions[, 2]
}

(baseline <- mean(pfun(rfo, newdata = fhb_train)))

# Estimate feature contributions for the test set:
fhb_test_X <- fhb_test %>% select(-Y) # features only!

set.seed(1051)  # for reproducibility
# Takes about 18 min with nsim = 1000
ex.all <- fastshap::explain(rfo, X = fhb_test_X, nsim = 1000, adjust = TRUE,  pred_wrapper = pfun)
save(fhb_test, ex.all, file = "shap.RData")

################## END SETUP ##################


## Libraries used after the SETUP section
library(tidyverse)
library(ggplot2)
library(ggforce)


## Function for plotting (from Smith and Alvarez https://doi.org/10.1016/j.simpa.2021.100074)
theme_bluewhite <- function (base_size = 11, base_family = "serif") {
  theme_bw() %+replace% 
    theme(
      text = element_text(family = "serif"),
      panel.grid.major  = element_line(color = "white"),
      panel.background = element_rect(fill = "grey97"),
      panel.border = element_rect(color = "darkred", fill = NA, size = 1), ##05014a
      axis.line = element_line(color = "grey97"),
      axis.ticks = element_line(color = "grey25"),
      axis.title = element_text(size = 10),
      axis.text = element_text(color = "grey25", size = 10),
      legend.title = element_text(size = 10),
      legend.text = element_text(size = 10),
      plot.title = element_text(size = 15, hjust = 0.5),
      strip.background = element_rect(fill = '#05014a'),
      strip.text = element_text(size = 10, colour = 'white'), # changes the facet wrap text size and color
      panel.grid.minor = element_blank(),
      legend.position = "bottom"
    )
}


## My modifications:
theme_bluewhite <- function (base_size = 11, base_family = "serif") {
  theme_light() %+replace% 
    theme(
      text = element_text(family = "serif"),
      # panel.grid.major  = element_line(color = "white"),
      # panel.background = element_rect(fill = "grey97"),
      # panel.border = element_rect(color = "darkred", fill = NA, size = 1), ##05014a
      # axis.line = element_line(color = "grey97"),
      axis.ticks = element_line(color = "grey25"),
      axis.title = element_text(size = 10),
      axis.text = element_text(color = "grey25", size = 10),
      legend.title = element_text(size = 10),
      legend.text = element_text(size = 10),
      plot.title = element_text(size = 15, hjust = 0.5),
      strip.background = element_rect(fill = '#05014a'),
      strip.text = element_text(size = 10, colour = 'white'), # changes the facet wrap text size and color
      panel.grid.minor = element_blank(),
      legend.position = "bottom"
    )
}


# Load the Shapley values and fhb_test data (assuming the file was created above):
load("shap.RData")


# Long format for the variable values (except resist), called rfvalue
foo1 <-
  fhb_test %>%
  dplyr::select(!resist, -Y) %>%
  dplyr::mutate(ID = 1:nrow(.), .before = everything()) %>%
  tidyr::pivot_longer(!ID, names_to = "variable", values_to = "rfvalue")

# Long format for the SHAP values:
foo2 <-
  ex.all %>%
  tibble::as_tibble() %>%
  dplyr::select(!resist) %>%
  dplyr::mutate(ID = 1:nrow(.), .before = everything()) %>%
  tidyr::pivot_longer(!ID, names_to = "variable", values_to = "value")

# Long format for stdvalue:
foo3 <- 
  fhb_test %>%
  dplyr::select(!resist, -Y) %>%
  dplyr::transmute(across(where(is.numeric), ~(.x - min(.x))/(max(.x) - min(.x)))) %>%
  dplyr::mutate(ID = 1:nrow(.), .before = everything()) %>%
  tidyr::pivot_longer(!ID, names_to = "variable", values_to = "stdfvalue")

# Merge into one tibble:
foo4 <- 
  dplyr::inner_join(foo1, foo2, by = c("ID", "variable")) %>%
  dplyr::inner_join(., foo3, by = c("ID", "variable"))
  


foo4 %>%
  ggplot() +
  coord_flip() +
  ggforce::geom_sina(aes(
    x = variable,
    y = value,
    color = stdfvalue),
    method = "counts", maxwidth = 1, size = 1, alpha = 0.8, seed = 648) +
  scale_color_gradient(
    low = "#FDE725FF",
    high = "darkblue",
    breaks = c(0, 1),
    labels = c("     Low", "     High"),
    guide = guide_colorbar(barwidth = 12, barheight = 0.3)) +
  geom_hline(yintercept = 0) +
  theme_bluewhite() +
  labs(x = "", y = "Shapley Value (impact on model output)", color = "Variable Value") +
  ggtitle("SHapley Additive exPlanations")
