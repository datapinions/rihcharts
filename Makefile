# Copyright (c) 2023 - Darren Erik Vengroff

# This Makefile coordinated the generation of impact
# charts for the Race+Income+Housing study. It requires
# input data files generated by the rihdata project.

################################################################
# The root of the rihdata project. In most cases it will
# have been checked out and built right next to this project.
# Normally, after running gmake in that directory to assemble
# all the data, you will come back here and run gmake to generate
# the impact plots.
################################################################
RIHDATA_ROOT := ../rihdata

# The year of U.S. Census ACS data that drives all of
# our analysis.
YEAR := 2021

# Pointers to the location of the data files and working files
# generated by the rihdata project. These should only change if
# the corresponding locations in the Makefile in $(RIHDATA_ROOT)
# change.
DATA_BUILD_DIR := $(RIHDATA_ROOT)/build-$(YEAR)
DATA_BUILD_WORKING_DIR := $(DATA_BUILD_DIR)/working
DATA_DIR := $(RIHDATA_ROOT)/data-$(YEAR)

# Plots made in the rihdata project.
RIH_PLOT_DIR := $(RIHDATA_ROOT)/plots-$(YEAR)
PRICE_PLOT_DIR := $(RIH_PLOT_DIR)/price-income
PRICE_FEATURE_PLOT_DIR := $(RIH_PLOT_DIR)/price-feature

# Local build.
BUILD_DIR := ./build-$(YEAR)
XGB_PARAMS_DIR := $(BUILD_DIR)/xgb-params

# Python config.
PYTHON = python3.11
LOGLEVEL = WARNING

# We will do our analysis on the top N CBASs. When testing
# and debugging, it is sometimes useful to override this
# with a smaller value on the command line. For example,
#
#    gmake N=3
#
# will only work with the three largest CBSAs.
N := 50

# A list of the top N CBSAs. This should have been constructed
# using the Makefile in $(RIHDATA_ROOT) for the same value of N.
TOP_N_LIST_FILE := $(DATA_BUILD_WORKING_DIR)/top_$(N)_$(YEAR)_cbsa.txt
TOP_N := $(shell cat $(TOP_N_LIST_FILE))

TOP_N_DATA := $(patsubst %,$(DATA_DIR)/%,$(TOP_N))

TOP_N_XGB_PARAMS := $(TOP_N_DATA:$(DATA_DIR)/%.geojson=$(XGB_PARAMS_DIR)/%.params.yaml)

# Where do plots go?
PLOT_DIR := ./plots-$(YEAR)
SHAP_PLOT_DIR := $(PLOT_DIR)/shap
SHAP_PLOT_XGB_DIR := $(SHAP_PLOT_DIR)/xgb
SHAP_PLOT_KNN_DIR := $(SHAP_PLOT_DIR)/knn

TOP_N_SHAP_PLOT_XGB_DIRS := $(TOP_N_DATA:$(DATA_DIR)/%.geojson=$(SHAP_PLOT_XGB_DIR)/%)
TOP_N_SHAP_PLOT_KNN_DIRS := $(TOP_N_DATA:$(DATA_DIR)/%.geojson=$(SHAP_PLOT_KNN_DIR)/%)

# Note that KNN is experimental and extremely slow.
TOP_N_SHAP_PLOT_DIRS := $(TOP_N_SHAP_PLOT_XGB_DIRS)  # $(TOP_N_SHAP_PLOT_KNN_DIRS)

# How to go from a data file for a single CBSA to a parameter file.
# for the same CBSA.
$(XGB_PARAMS_DIR)/%.params.yaml: $(DATA_DIR)/%.geojson
	mkdir -p $(@D)
	$(PYTHON) -m rih.treegress --log $(LOGLEVEL) -v $(YEAR) $(GROUP_HISPANIC_LATINO) -o $@ $<

# How to build the file that ranks the CBSAs by score. This is a
# summary file that is useful for undeRstanding which CBSAs fit
# well and which did not fit as well. It requires
# a parameter file from each of the top N CBSAs. It also requires
# a linear regression results file for each of them, since it puts
# these scores in the output file also.
$(RANKED_FILE): $(TOP_N_XGB_PARAMS) $(TOP_N_LINREG)
	mkdir -p $(@D)
	$(PYTHON) -m rih.rankscore -o $@ $(TOP_N_XGB_PARAMS)

# Produce a series of plots for the influence of each of several
# features on the output of the model for a single CBSA. All of
# the block groups in that CBSA are considered. Since the shap analysis
# is the slow part of this, and it produces values for all features at
# the same time, we organize the code so that one executable produces
# plots for all features.
$(SHAP_PLOT_DIR)/xgb/%: $(XGB_PARAMS_DIR)/%.params.yaml $(DATA_DIR)/%.geojson
	mkdir -p $@
	$(PYTHON) -m rih.charts.shapplot --log $(LOGLEVEL) --background -v $(YEAR) $(GROUP_HISPANIC_LATINO) -t $(XGB_PARAMS_DIR)/$*.params.yaml -o $@ $(DATA_DIR)/$*.geojson
	touch $@

$(SHAP_PLOT_DIR)/knn/%: $(XGB_PARAMS_DIR)/%.params.yaml $(DATA_DIR)/%.geojson
	mkdir -p $@
	$(PYTHON) -m rih.charts.shapplot --log $(LOGLEVEL) -m knn --background -v $(YEAR) $(GROUP_HISPANIC_LATINO) -t $(XGB_PARAMS_DIR)/$*.params.yaml -o $@ $(DATA_DIR)/$*.geojson
	touch $@

# An output file that ranks the performance of the model
# on the top N CBSAs. This is the top level output that
# our default targer `all` builds along with plots.
RANKED_FILE :=  $(XGB_PARAMS_DIR)/ranked_$(N)_$(YEAR)_cbsa.csv

# Templates and related details for rendering the site.
HTML_TEMPLATE_DIR := ./templates
STATIC_HTML_DIR := ./static-html
SITE_DIR := $(BUILD_DIR)/site
SITE_IMAGE_DIR := $(SITE_DIR)/images

HTML_NAMES := impact.html
SITE_HTML := $(HTML_NAMES:%=$(SITE_DIR)/%)
HTML_TEMPLATES := $(HTML_NAMES:%.html=$(HTML_TEMPLATE_DIR)/%.html.j2)

.PHONY: all shap_plots site_html clean clean_plots params list_top_n

all: shap_plots

params: $(TOP_N_XGB_PARAMS)

shap_plots: $(TOP_N_SHAP_PLOT_DIRS)

site_html: $(SITE_HTML) $(SITE_PLOTS) $(SITE_IMAGE_DIR)/impact_charts $(SITE_IMAGE_DIR)/price_charts
	cp -r $(STATIC_HTML_DIR)/* $(SITE_DIR)

$(SITE_IMAGE_DIR)/impact_charts: $(TOP_N_SHAP_PLOT_DIRS)
	-rm -rf $@
	mkdir -p $@
	cp -r $(SHAP_PLOT_DIR)/xgb/* $@

$(SITE_IMAGE_DIR)/price_charts: $(PRICE_FEATURE_PLOT_DIR) $(PRICE_PLOT_DIR)
	-rm -rf $@
	mkdir -p $@
	cp -r $(PRICE_FEATURE_PLOT_DIR)/* $@
	cp -r $(PRICE_PLOT_DIR)/* $@

clean: clean_plots
	rm -rf $(BUILD_DIR)

clean_plots:
	rm -rf $(PLOT_DIR)

# How to render and HTML template for the site.
$(SITE_DIR)/%.html: $(HTML_TEMPLATE_DIR)/%.html.j2
	mkdir -p $(@D)
	$(PYTHON) -m rih.rendersite --log $(LOGLEVEL)  -v $(YEAR) -t $(TOP_N_LIST_FILE) -o $@ $<

# Mainly for debugging.
list_top_n:
	@echo 'Data files:'
	@printf '%s\n' $(TOP_N_DATA)
	@echo 'Plot files:'
	@printf '%s\n' $(TOP_N_SHAP_PLOT_DIRS)



