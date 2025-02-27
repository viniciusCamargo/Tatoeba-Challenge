# -*-makefile-*-
#
#------------------------------------------------------------
#
# build scripts for data sets of the
# Tatoeba Translation Challenge
#
# https://github.com/Helsinki-NLP/Tatoeba-Challenge
#------------------------------------------------------------
##
## TODO: add clean-up recipes
## TODO: get rid of some hard-coded paths
## TODO: properly integrate software dependencies
## TODO: integrate more data filters (OPUS-Filter?)
##
##
## make VERSION=`date +%F` all . make a new release
## make update ................. update test data with latest Tatoeba data
## make cleanup ................ some cleanup in tatoeba data release dirs
##
##--------------------------------------------------------------------
## working with Tatoeba-MT models
##
## make update-models .......... update the model releases
##
## make cleanup-model-dirs ..... remove duplicates in released model dir
## make upload-models .......... upload models in release-dir
## make released-model-list .... generate a list of released models
## make released-model-results . generate results tables
## make update-git ............. update the git repository
##

## OPUS home directory and language code conversion tools
## OPUSMT_HOMEDIR: local copy of Opus-MT-train project
## TODO: get rid of some hard-coded paths?

OPUS_HOME      = /projappl/nlpl/data/OPUS
OPUSMT_HOMEDIR = ../Opus-MT-train


## VERSION = date of today
## TATOEBA_VERSION: latest Tatoeba release in OPUS

TODAY          := $(shell date +%F)
# VERSION         = v$(shell date +%F)
VERSION         = v20190709
TATOEBA_VERSION = ${notdir ${shell realpath ${OPUS_HOME}/Tatoeba/latest 2>/dev/null}}



## corpora in OPUS used for training
## exclude Tatoeba (= test/dev data), WMT-News (reserve for comparison with other models)
## TODO: do we want to / need toexclude some other data sets?

OPUS_CORPORA    := ${sort ${notdir ${shell find ${OPUS_HOME} -maxdepth 1 -mindepth 1 -type d}}}
EXCLUDE_CORPORA := Tatoeba WMT-News MPC1
TRAIN_CORPORA   := ${filter-out ${EXCLUDE_CORPORA},${OPUS_CORPORA}}


## Tatoeba MT models
## - release directory
## - data container on allas

MODEL_RELEASEDIR = models
MODEL_CONTAINER = Tatoeba-MT-models


## some more tools and parameters
## - check if there is dedicated scratch space (e.g. on puhti nodes)
## - check if terashuf and pigz are available

ifdef LOCAL_SCRATCH
  TMPDIR = ${LOCAL_SCRATCH}
endif

## scripts and tools

SCRIPTDIR      = scripts
TOKENIZER      = ${SCRIPTDIR}/moses/tokenizer
ISO639         = iso639
GET_ISO_CODE   = ${ISO639} -m
# GET_ISO_CODE = ${ISO639} -m -k


## set additional argument options for opus_read (if it is used)
## e.g. OPUSREAD_ARGS = -a certainty -tr 0.3
## TODO: should we always use opus_read instead of pre-extracted moses-style files?
##       (disadvantage: much slower!)
OPUSREAD_ARGS =

THREADS ?= 4
SORT = sort -T ${TMPDIR} --parallel=${THREADS}
SHUFFLE = ${shell which terashuf 2>/dev/null}
ifeq (${SHUFFLE},)
  SHUFFLE = ${SORT} --random-sort
endif
GZIP := ${shell which pigz 2>/dev/null}
GZIP ?= gzip
ZCAT := ${GZIP} -cd

## basic training data filtering pipeline

BASIC_FILTERS = | perl -CS -pe 'tr[\x{9}\x{A}\x{D}\x{20}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}][]cd;' \
		| perl -CS -pe 's/\&\s*\#\s*160\s*\;/ /g' \
		| perl -pe 's/[\p{C}-[\n\t]]/ /g;' \
		| recode -f utf8..utf16 | recode -f utf16..utf8 \
		| $(TOKENIZER)/deescape-special-chars.perl


## available OPUS languages (IDs in the way they appear in the corpus)
## (skip 'simple' = simple English in Wikipedia in the English data sets)

ifneq (${wildcard opus-langs.txt},)
  OPUS_LANGS = ${filter-out simple,${shell head -1 opus-langs.txt}}
endif
ifneq (${wildcard opus-langpairs3.txt},)
  OPUS_PAIRS3 = ${filter-out simple,${shell head -1 opus-langpairs.txt}}
endif

## all languages in the current Tatoeba data set in OPUS

TATOEBA_LANGS = ${sort ${patsubst %.txt.gz,%,${notdir ${wildcard ${OPUS_HOME}/Tatoeba/${TATOEBA_VERSION}/mono/*.txt.gz}}}}
TATOEBA_PAIRS = ${sort ${patsubst %.xml.gz,%,${notdir ${wildcard ${OPUS_HOME}/Tatoeba/${TATOEBA_VERSION}/xml/*.xml.gz}}}}


## ISO-639-3 language codes

OPUS_LANGS3       = ${sort ${filter-out xxx,${shell ${GET_ISO_CODE} ${OPUS_LANGS}}}}
TATOEBA_LANGS3    = ${sort ${filter-out xxx,${shell ${GET_ISO_CODE} ${TATOEBA_LANGS}}}}
TATOEBA_PAIRS3    = ${sort ${shell ${SCRIPTDIR}/convert_langpair_codes.pl ${TATOEBA_PAIRS}}}


## data directories

DATADIR     = data
RELEASEDIR  = ${DATADIR}/release/${VERSION}
DEVTESTDIR  = ${DATADIR}/devtest
TESTDATADIR = ${DATADIR}/test
DEVDATADIR  = ${DATADIR}/dev
INFODIR     = ${RELEASEDIR}

# RELEASEDIR  = ${DATADIR}/release
# DEVTESTDIR  = ${DATADIR}/devtest
# TESTDATADIR = ${DATADIR}/test
# DEVDATADIR  = ${DATADIR}/dev
# INFODIR     = ${RELEASEDIR}



## all data files we need to produce

TRAIN_DATA  = ${patsubst %,${RELEASEDIR}/%/train.id.gz,${TATOEBA_PAIRS3}}
TEST_DATA   = ${patsubst %,${RELEASEDIR}/%/test.id,${TATOEBA_PAIRS3}}
DEV_DATA    = ${patsubst %,${RELEASEDIR}/%/dev.id,${TATOEBA_PAIRS3}}
TEST_TSV    = ${patsubst ${RELEASEDIR}/%.id,${DATADIR}/test/%.txt,${wildcard ${RELEASEDIR}/*/test.id}}
DEV_TSV     = ${patsubst ${RELEASEDIR}/%.id,${DATADIR}/dev/%.txt,${wildcard ${RELEASEDIR}/*/dev.id}}
LANGIDS     = ${patsubst %,${INFODIR}/%/langids,${TATOEBA_PAIRS3}}
OVERLAPTEST = ${patsubst ${RELEASEDIR}/%/train.id.gz,${INFODIR}/%/overlap-with-test,${wildcard ${RELEASEDIR}/*/train.id.gz}}
OVERLAPDEV  = ${patsubst ${RELEASEDIR}/%/train.id.gz,${INFODIR}/%/overlap-with-dev,${wildcard ${RELEASEDIR}/*/train.id.gz}}


## this is for regular updates of testdata with new Tatoeba releases in OPUS
## call `make update-testdata`
UPDATED_TEST_DATA = ${patsubst %,${DEVTESTDIR}/%/test-${TATOEBA_VERSION}.txt,${TATOEBA_PAIRS3}}







## statistics of all files
STATISTICS  = Data-${VERSION}.md


DOWNLOADURL        := https://object.pouta.csc.fi
TATOEBA_DATAURL    := https://object.pouta.csc.fi/Tatoeba-Challenge
TATOEBA_MODELURL   := https://object.pouta.csc.fi/Tatoeba-MT-models

TATOEBA_CONTAINER   = Tatoeba-Challenge
RELEASE_CONTAINER   = Tatoeba-Challenge-${VERSION}
WIKIDOC_CONTAINER   = Tatoeba-Challenge-WikiDoc-${VERSION}
WIKISHUF_CONTAINER  = Tatoeba-Challenge-WikiShuffled-${VERSION}



PIVOT_LANG ?= eng
EXTRA_OPUS_LANGS3 = ${filter-out ${TATOEBA_LANGS3},${OPUS_LANGS3}}
EXTRA_OPUS_PAIRS3 = ${filter-out ${TATOEBA_PAIRS3},\
		     ${shell cat opus-langpairs3.txt | tr ' ' "\n" |\
			     grep '${PIVOT_LANG}' | grep -v xxx | grep '^...-...$$'}}

EXTRA_TRAIN_DATA  = ${patsubst %,${RELEASEDIR}/%/train.id.gz,${EXTRA_OPUS_PAIRS3}}


## monolingual data taken from Wikimedia sources
## prepared by the Opus-MT-train project

OPUSMT_WIKIDIR = ${OPUSMT_HOMEDIR}/backtranslate/wikidoc
# WIKI_LANGS   = ${notdir ${wildcard ${OPUSMT_WIKIDIR}/*}}
WIKI_LANGS     = aa ab ace ady af ak als am an ang ar arc ary arz as ast atj av awa ay az azb ba ban bar bcl be bg bh bi bjn bm bn bo bpy br bs bug bxr ca cdo ce ceb ch cho chr chy ckb co cr crh cs csb cu cv cy da de din diq dsb dty dv dz ee el eml en eo es et eu ext fa ff fi fj fo fr frp frr fur fy ga gag gan gcr gd gl glk gn gom gor got gu gv ha hak haw he hi hif ho hr hsb ht hu hy hyw hz ia id ie ig ii ik ilo inh io is it iu ja jam jbo jv ka kaa kab kbd kbp kg ki kj kk kl km kn ko koi kr krc ks ksh ku kv kw ky la lad lb lbe lez lfn lg li lij lmo ln lo lrc lt ltg lv mai mdf mg mh mhr mi min mk ml mn mnw mr mrj ms mt mus mwl my myv mzn na nah nap nds ne new ng nl nn no nov nqo nrm nso nv ny oc olo om or os pa pag pam pap pcd pdc pfl pi pih pl pms pnb pnt ps pt qu rm rmy rn ro ru rue rw sa sah sat sc scn sco sd se sg sh shn si sk sl sm sn so sq sr srn ss st stq su sv sw szl szy ta tcy te ten tet tg th ti tk tl tn to tpi tr ts tt tum tw ty tyv udm ug uk ur uz ve vec vep vi vls vo wa war wo wuu xal xh xmf yi yo za zea zh zu
WIKI_LANGS3    = ${sort ${filter-out xxx,${shell ${GET_ISO_CODE} ${WIKI_LANGS}}}}

WIKI_DOCS      = ${patsubst %,${RELEASEDIR}/%/wikipedia.id.gz,${WIKI_LANGS3}} \
		 ${patsubst %,${RELEASEDIR}/%/wikibooks.id.gz,${WIKI_LANGS3}} \
		 ${patsubst %,${RELEASEDIR}/%/wikinews.id.gz,${WIKI_LANGS3}} \
		 ${patsubst %,${RELEASEDIR}/%/wikiquote.id.gz,${WIKI_LANGS3}} \
		 ${patsubst %,${RELEASEDIR}/%/wikisource.id.gz,${WIKI_LANGS3}}



## new lang ID files with normalised codes and script info

NEW_TEST_IDS  = ${patsubst ${RELEASEDIR}/%.ids,${RELEASEDIR}/%.id,${wildcard ${RELEASEDIR}/*/test.ids}}
NEW_DEV_IDS   = ${patsubst ${RELEASEDIR}/%.ids,${RELEASEDIR}/%.id,${wildcard ${RELEASEDIR}/*/dev.ids}}
NEW_TRAIN_IDS = ${patsubst ${RELEASEDIR}/%.ids.gz,${RELEASEDIR}/%.id.gz,${wildcard ${RELEASEDIR}/*/train.ids.gz}}



.PHONY: all data testdata devdata traindata statistics test-tsv dev-tsv
.PHONY: upload upload-test upload-devtest upload-train upload-mono
.PHONY: extra-traindata extra-statistics extra-upload
.PHONY: update update-testdata

all: opus-langs.txt
	${MAKE} data
	${MAKE} dev-tsv test-tsv
	${MAKE} Data.md
	${MAKE} subsets
	${MAKE} extra-traindata
	${MAKE} extra-statistics


data: ${TEST_DATA} ${DEV_DATA} ${TRAIN_DATA}
traindata: ${TRAIN_DATA}
testdata: ${TEST_DATA}
devdata: ${DEV_DATA}

## this is for regular updates of testdata with new Tatoeba releases in OPUS
## call `make update-testdata`
update update-testdata: ${UPDATED_TEST_DATA}

test-tsv: ${TEST_TSV}
dev-tsv: ${DEV_TSV}
langids: ${DATADIR}/langids-train.txt ${DATADIR}/langids-dev.txt ${DATADIR}/langids-test.txt \
	${DATADIR}/langids-common.txt ${DATADIR}/langids-train-only.txt ${DATADIR}/langids-devtest-only.txt
statistics: ${STATISTICS}
overlaps: ${OVERLAPTEST} ${OVERLAPDEV}

upload: upload-test upload-dev upload-devtest upload-train upload-mono
upload-devtest: ${DEVTESTDIR}.done
upload-test: ${TESTDATADIR}-${VERSION}.done
upload-dev: ${DEVDATADIR}-${VERSION}.done
upload-train: ${patsubst %,${RELEASEDIR}/%.done,${TATOEBA_PAIRS3}}
upload-mono: ${patsubst %,${RELEASEDIR}/%.done,${WIKI_LANGS3}}
upload-wikishuffled: ${patsubst wiki-shuffled/%,${RELEASEDIR}/wiki-shuffled-%.done,${wildcard wiki-shuffled/???}}
upload-wikidoc: ${patsubst wiki-doc/%,${RELEASEDIR}/wiki-doc-%.done,${wildcard wiki-doc/???}}


.PHONY: update-models
update-models:
	${MAKE} cleanup-model-dirs
	${MAKE} upload-models
	${MAKE} released-model-list
	${MAKE} released-model-results
	git add ${MODEL_RELEASEDIR}/*/README.md
	git add ${MODEL_RELEASEDIR}/*/*.yml
	${MAKE} GIT_COMMIT_MESSAGE='latest models added' update-git

GIT_COMMIT_MESSAGE ?= latest changes

.PHONY: update-git
update-git:
	git commit -am "${GIT_COMMIT_MESSAGE}"
	git push origin master

.PHONY: upload-models
upload-models:
	which a-put
	find ${MODEL_RELEASEDIR}/ -type l | tar -cf models-links.tar -T -
	find ${MODEL_RELEASEDIR}/ -type l -delete
	cd ${MODEL_RELEASEDIR} && swift upload ${MODEL_CONTAINER} --changed --skip-identical *
	tar -xf models-links.tar
	rm -f models-links.tar
	swift post ${MODEL_CONTAINER} --read-acl ".r:*"
	swift list ${MODEL_CONTAINER} > index.txt
	swift upload ${MODEL_CONTAINER} index.txt
	rm -f index.txt


.PHONY: released-model-list
released-model-list: 	models/released-models.txt \
			models/released-model-results.txt \
			models/released-model-results-all.txt \
			models/released-model-results-other.txt
#			models/released-model-languages.txt


RESULT_FILES = results/tatoeba-results-all.md \
	results/tatoeba-results-all-subset-zero.md \
	results/tatoeba-results-all-subset-lowest.md \
	results/tatoeba-results-all-subset-lower.md \
	results/tatoeba-results-all-subset-medium.md \
	results/tatoeba-results-all-subset-higher.md \
	results/tatoeba-results-all-subset-highest.md

.PHONY: released-model-results results
released-model-results results: ${RESULT_FILES} results/tatoeba-models-all.md


released-model-maps: 	model-map-src2trg-all.html model-map-trg2src-all.html \
			model-map-src2trg.html model-map-trg2src.html

MODEL_ALLMAP_WARNING = <p><b>IMPORTANT NOTE: Some of the test sets used in measuring translation quality are WAY TOO SMALL to be reliable! Some of them include only a few lines of reference translations!</b></p>

MODEL_MAP_WARNING = <p><b>IMPORTANT NOTE: Some of the test sets used in measuring translation quality are very small and will not be reliable! Check the details in the Tatoeba MT Challenge benchmark releases!</b></p>

SRC2TRG_MAP_DESCRIPTION = <p>Available translation models for various language pairs. Colors indicate the quality on a scale from red (bad) to green (best) measured by chr-F2 scores. Click on the dots to get more information about the language pair and to get links for downloading the model.</p> \
	<p>The dots on the map indicate the source language. Select the target language from the menu in the upper-right corner of the map.</p>

TRG2SRC_MAP_DESCRIPTION = <p>Available translation models for various language pairs. Colors indicate the quality on a scale from red (bad) to green (best) measured by chr-F2 scores. Click on the dots to get more information about the language pair and to get links for downloading the model.</p> \
	<p>The dots on the map indicate the target language. Select the source language from the menu in the upper-right corner of the map.</p>


FIX_LANG_CODES = sed 	-e 's/kur_Latn/kmr/' \
			-e 's/kur_Arab/ckb/' \
			-e 's/fas/pes/' \
			-e 's/sqi/sqj/' \

## double check (move macro language swahili to individual lang swahili?)
#
#			-e 's/swa/swh/'


model-map-src2trg-all.html: models/released-model-results-all.txt
	python3 scripts/create-map.py < $< > ${@:.html=.json}
	cat scripts/create-src2trg-map.js >> ${@:.html=.json}
	cat scripts/create-map.html-template |\
	sed -e 's#__TITLE__#Tatoeba MT Challenge - Pre-trained NMT models (source language plot)#' \
	    -e 's#__DESCRIPTION__#${SRC2TRG_MAP_DESCRIPTION}${MODEL_ALLMAP_WARNING}#' \
	    -e 's#__JSONFILE__#${@:.html=.json}#' > $@

model-map-trg2src-all.html: models/released-model-results-all.txt
	python3 scripts/create-map.py -t < $< > ${@:.html=.json}
	cat scripts/create-trg2src-map.js >> ${@:.html=.json}
	cat scripts/create-map.html-template |\
	sed -e 's#__TITLE__#Tatoeba MT Challenge - Pre-trained NMT models (target language plot)#' \
	    -e 's#__DESCRIPTION__#${TRG2SRC_MAP_DESCRIPTION}${MODEL_ALLMAP_WARNING}#' \
	    -e 's#__JSONFILE__#${@:.html=.json}#' > $@

model-map-src2trg.html: models/released-model-results.txt
	python3 scripts/create-map.py < $< > ${@:.html=.json}
	cat scripts/create-src2trg-map.js >> ${@:.html=.json}
	cat scripts/create-map.html-template |\
	sed -e 's#__TITLE__#Tatoeba MT Challenge - Pre-trained NMT models (source language plot)#' \
	    -e 's#__DESCRIPTION__#${SRC2TRG_MAP_DESCRIPTION}${MODEL_MAP_WARNING}#' \
	    -e 's#__JSONFILE__#${@:.html=.json}#' > $@

model-map-trg2src.html: models/released-model-results.txt
	python3 scripts/create-map.py -t < $< > ${@:.html=.json}
	cat scripts/create-trg2src-map.js >> ${@:.html=.json}
	cat scripts/create-map.html-template |\
	sed -e 's#__TITLE__#Tatoeba MT Challenge - Pre-trained NMT models (target language plot)#' \
	    -e 's#__DESCRIPTION__#${TRG2SRC_MAP_DESCRIPTION}${MODEL_MAP_WARNING}#' \
	    -e 's#__JSONFILE__#${@:.html=.json}#' > $@




print-extra-traindata:
	for l in ${EXTRA_TRAIN_DATA}; do \
	  if [ ! -e $$l ]; then \
		echo $$l; \
	  fi \
	done

#	@echo ${sort ${EXTRA_TRAIN_DATA}} | tr ' ' "\n"



## extra training data where we don't have any 
## tatoeba test data (only paired with PIVOT_LANG (English))
extra-traindata: ${EXTRA_TRAIN_DATA}
extra-statistics:
	${MAKE} STATISTICS=subsets/NoTestData-${VERSION}.md \
		TATOEBA_PAIRS3="${EXTRA_OPUS_PAIRS3}" statistics
extra-upload: ${patsubst %,${RELEASEDIR}/%.done,${EXTRA_OPUS_PAIRS3}}


## list of all languages in OPUS
opus-langs.txt:
	wget -O $@.tmp http://opus.nlpl.eu/opusapi/?languages=true
	grep '",' $@.tmp | tr '",' '  ' | sort | tr "\n" ' ' | sed 's/  */ /g' > $@
	rm -f $@.tmp

## all language pairs in opus in one file
opus-langpairs.txt:
	for l in ${OPUS_LANGS}; do \
	  wget -O $@.tmp http://opus.nlpl.eu/opusapi/?source=$$l\&languages=true; \
	  grep '",' $@.tmp | tr '",' '  ' | sort | tr "\n" ' ' | sed 's/  */ /g' > $@.tmp2; \
	  for t in `cat $@.tmp2`; do \
	    if [ $$t \< $$l ]; then \
	      echo "$$t-$$l" >> $@.all; \
	    else \
	      echo "$$l-$$t" >> $@.all; \
	    fi \
	  done; \
	  rm -f $@.tmp $@.tmp2; \
	done
	tr ' ' "\n" < $@.all |\
	sed 's/ //g' | sort -u | tr "\n" ' ' > $@
	rm -f $@.all

## opus language pairs in ISO639-3 codes
opus-langpairs3.txt: opus-langpairs.txt
	cat $< | xargs ${SCRIPTDIR}/convert_langpair_codes.pl | \
	tr ' ' "\n" | sort -u | tr "\n" ' ' | sed 's/ $$//' > $@


## language IDs in training/dev/test

${RELEASEDIR}/langids-train.txt: # ${LANGIDS}
	find ${RELEASEDIR} -name langids | xargs cat | grep 'train ' | \
	cut -f2 | tr ' ' "\n" | sort -u > $@

${RELEASEDIR}/langids-test.txt: # ${LANGIDS}
	find ${RELEASEDIR} -name langids | xargs cat | grep 'test ' | \
	cut -f2 | tr ' ' "\n" | sort -u > $@

${DATADIR}/langids-dev.txt: # ${LANGIDS}
	find ${RELEASEDIR} -name langids | xargs cat | grep 'dev ' | \
	cut -f2 | tr ' ' "\n" | sort -u > $@

${DATADIR}/langids-devtest.txt: ${DATADIR}/langids-dev.txt ${DATADIR}/langids-test.txt
	cat $^ | sort -u | grep . > $@

${DATADIR}/langids-common.txt: ${DATADIR}/langids-train.txt ${DATADIR}/langids-devtest.txt
	comm -1 -2 $^ | grep . > $@

${DATADIR}/langids-train-only.txt: ${DATADIR}/langids-train.txt ${DATADIR}/langids-devtest.txt
	comm -2 -3 $^ | grep . > $@

${DATADIR}/langids-devtest-only.txt: ${DATADIR}/langids-train.txt ${DATADIR}/langids-devtest.txt
	comm -1 -3 $^ | grep . > $@



## cleanup some orphan files and directories
cleanup:
	-for d in ${EXTRA_OPUS_PAIRS3}; do \
	  if [ -e ${RELEASEDIR}/$$d/train.d ]; then \
	    rm -f ${RELEASEDIR}/$$d/train.d/*; \
	    rmdir ${RELEASEDIR}/$$d/train.d; \
	  fi; \
	  rmdir ${RELEASEDIR}/$$d; \
	done


## some minor fixes with uncommon langIDs in OPUS data
FIXLANGIDS = | sed 's/ze_zh/zh/g;s/_Hani//g;s/-han[st]//g;s/zht/zh_TW/g;s/zhs/zh_CN/g'

## create training data by concatenating all data sets
## using normalized language codes (macro-languages)

${RELEASEDIR}/%/train.id.gz:
	@echo "make train data for ${patsubst ${RELEASEDIR}/%/train.id.gz,%,$@}"
	@rm -f $@.tmp1 $@.tmp2
	@mkdir -p ${dir $@}train.d
	@( l=${patsubst ${RELEASEDIR}/%/train.id.gz,%,$@}; \
	  s=${firstword ${subst -, ,${patsubst ${RELEASEDIR}/%/train.id.gz,%,$@}}}; \
	  t=${lastword ${subst -, ,${patsubst ${RELEASEDIR}/%/train.id.gz,%,$@}}}; \
	  E=`${SCRIPTDIR}/find_opus_langs.pl $$s ${OPUS_LANGS}`; \
	  F=`${SCRIPTDIR}/find_opus_langs.pl $$t ${OPUS_LANGS}`; \
	  for e in $$E; do \
	    for f in $$F; do \
		if [ $$e == $$f ]; then a=$${e}1;b=$${f}2; \
		                   else a=$${e};b=$${f}; fi; \
		for c in ${TRAIN_CORPORA}; do \
		  if [ -e ${OPUS_HOME}/$$c/latest/moses/$$e-$$f.txt.zip ]; then \
		    echo "get all $$c data for $$s-$$t ($$e-$$f)"; \
		    unzip -qq -n -d ${dir $@}train.d ${OPUS_HOME}/$$c/latest/moses/$$e-$$f.txt.zip; \
		    paste ${dir $@}train.d/*.$$a ${dir $@}train.d/*.$$b ${BASIC_FILTERS} |\
		    ${SCRIPTDIR}/bitext-match-lang.py -s $$e -t $$f   > $@.tmp2; \
		    rm -f ${dir $@}train.d/*; \
		  elif [ -e ${OPUS_HOME}/$$c/latest/moses/$$f-$$e.txt.zip ]; then \
		    echo "get all $$c data for $$s-$$t ($$e-$$f)"; \
		    unzip -qq -n -d ${dir $@}train.d ${OPUS_HOME}/$$c/latest/moses/$$f-$$e.txt.zip; \
		    paste ${dir $@}train.d/*.$$a ${dir $@}train.d/*.$$b ${BASIC_FILTERS} |\
		    ${SCRIPTDIR}/bitext-match-lang.py -s $$e -t $$f   > $@.tmp2; \
		    rm -f ${dir $@}train.d/*; \
		  elif 	[ -e ${OPUS_HOME}/$$c/latest/xml/$$e-$$f.xml.gz ] || \
			[ -e ${OPUS_HOME}/$$c/latest/xml/$$f-$$e.xml.gz ]; then \
		    echo "opus-read $$c ($$e-$$f)!"; \
		    opus_read ${OPUSREAD_ARGS} -q -ln -rd ${OPUS_HOME} \
				-d $$c -s $$e -t $$f -wm moses -p raw ${BASIC_FILTERS} |\
		    ${SCRIPTDIR}/bitext-match-lang.py -s $$e -t $$f   > $@.tmp2; \
		  fi; \
		  if [ -e $@.tmp2 ]; then \
		    v=`realpath ${OPUS_HOME}/$$c/latest | sed 's#${OPUS_HOME}/$$c/##'`; \
		    cut -f1 $@.tmp2 ${FIXLANGIDS} | langscript -3 -l $$e -r -D  > $@.tmp2srcid; \
		    cut -f2 $@.tmp2 ${FIXLANGIDS} | langscript -3 -l $$f -r -D  > $@.tmp2trgid; \
		    paste $@.tmp2srcid $@.tmp2trgid $@.tmp2 | sed "s/^/$$c-$$v	/"  >> $@.tmp1; \
		    rm -f $@.tmp2 $@.tmp2srcid $@.tmp2trgid; \
		  fi \
		done \
	    done \
	  done \
	)
	if [ -s $@.tmp1 ]; then \
	  ${SHUFFLE} < $@.tmp1 > $@.tmp2; \
	  cut -f4 $@.tmp2 | ${GZIP} -c > ${dir $@}train.src.gz; \
	  cut -f5 $@.tmp2 | ${GZIP} -c > ${dir $@}train.trg.gz; \
	  cut -f1,2,3 $@.tmp2 | ${GZIP} -c > $@; \
	fi
	rm -f $@.tmp1 $@.tmp2
	rmdir ${dir $@}train.d


## make test and dev data
## split shuffled Tatoeba data

${DEVTESTDIR}/%/tatoeba-shuffled.tsv:
	@rm -f $@.tmp1 $@.tmp2
	@mkdir -p ${dir $@}tatoeba.d
	@( l=${patsubst ${DEVTESTDIR}/%/test.id,%,$@}; \
	  s=${firstword ${subst -, ,${patsubst ${DEVTESTDIR}/%/,%,${dir $@}}}}; \
	  t=${lastword  ${subst -, ,${patsubst ${DEVTESTDIR}/%/,%,${dir $@}}}}; \
	  E=`${SCRIPTDIR}/find_opus_langs.pl $$s ${TATOEBA_LANGS}`; \
	  F=`${SCRIPTDIR}/find_opus_langs.pl $$t ${TATOEBA_LANGS}`; \
	  for e in $$E; do \
	    for f in $$F; do \
		if [ $$e == $$f ]; then a=$${e}1;b=$${f}2; \
		                   else a=$${e};b=$${f}; fi; \
		if [ -e ${OPUS_HOME}/Tatoeba/${TATOEBA_VERSION}/moses/$$e-$$f.txt.zip ]; then \
		  echo "get all Tatoeba data for $$s-$$t ($$e-$$f)"; \
		  echo "unzip -qq -n -d ${dir $@}tatoeba.d ${OPUS_HOME}/Tatoeba/${TATOEBA_VERSION}/moses/$$e-$$f.txt.zip"; \
		  unzip -qq -n -d ${dir $@}tatoeba.d ${OPUS_HOME}/Tatoeba/${TATOEBA_VERSION}/moses/$$e-$$f.txt.zip; \
		  cat ${dir $@}tatoeba.d/*.$$a | langscript -3 -l $$e -r -D > $@.tmp1id; \
		  cat ${dir $@}tatoeba.d/*.$$b | langscript -3 -l $$f -r -D  > $@.tmp2id; \
		  paste $@.tmp1id ${dir $@}tatoeba.d/*.$$a >> $@.tmp1; \
		  paste $@.tmp2id ${dir $@}tatoeba.d/*.$$b >> $@.tmp2; \
		  rm -f $@.tmp1id $@.tmp2id ${dir $@}tatoeba.d/*; \
		elif [ -e ${OPUS_HOME}/Tatoeba/${TATOEBA_VERSION}/moses/$$f-$$e.txt.zip ]; then \
		  echo "get all Tatoeba data for $$s-$$t ($$e-$$f)"; \
		  unzip -qq -n -d ${dir $@}tatoeba.d ${OPUS_HOME}/Tatoeba/${TATOEBA_VERSION}/moses/$$f-$$e.txt.zip; \
		  cat ${dir $@}tatoeba.d/*.$$a | langscript -3 -l $$e -r -D > $@.tmp1id; \
		  cat ${dir $@}tatoeba.d/*.$$b | langscript -3 -l $$f -r -D > $@.tmp2id; \
		  paste $@.tmp1id ${dir $@}tatoeba.d/*.$$a >> $@.tmp1; \
		  paste $@.tmp2id ${dir $@}tatoeba.d/*.$$b >> $@.tmp2; \
		  rm -f $@.tmp1id $@.tmp2id ${dir $@}tatoeba.d/*; \
		fi \
	    done \
	  done \
	)
	@paste $@.tmp1 $@.tmp2 | shuf | awk -F"\t" '{print $$1,$$3,$$2,$$4}' OFS="\t" > $@
	@rm -f $@.tmp1 $@.tmp2
	@rmdir ${dir $@}tatoeba.d


## test data in the release: merge all cumulated test data in data/devtest

${RELEASEDIR}/%/test.id: 
	${MAKE} $(patsubst ${RELEASEDIR}/%/test.id,${DEVTESTDIR}/%/test-${TATOEBA_VERSION}.txt,$@)
	mkdir -p ${dir $@}
	cat ${patsubst ${RELEASEDIR}/%/test.id,${DEVTESTDIR}/%,$@}/test-*.txt > $@.merged
	cut -f1,2 $@.merged > $@
	cut -f3 $@.merged > ${dir $@}test.src
	cut -f4 $@.merged > ${dir $@}test.trg
	rm -f $@.merged

## dev data in the release: merge all cumulated dev data in data/devtest

${RELEASEDIR}/%/dev.id: 
	${MAKE} ${patsubst ${RELEASEDIR}/%/dev.id,${DEVTESTDIR}/%/dev-${TATOEBA_VERSION}.txt,$@}
	mkdir -p ${dir $@}
	cat ${patsubst ${RELEASEDIR}/%/dev.id,${DEVTESTDIR}/%,$@}/dev-*.txt > $@.merged
	cut -f1,2 $@.merged > $@
	cut -f3 $@.merged > ${dir $@}dev.src
	cut -f4 $@.merged > ${dir $@}dev.trg
	rm -f $@.merged


## add test and dev data from the Tatoeba release

${DEVTESTDIR}/%/test-${TATOEBA_VERSION}.txt: ${DEVTESTDIR}/%/tatoeba-shuffled.tsv
	@echo "make test and dev-data for ${patsubst ${DEVTESTDIR}/%/,%,${dir $@}}"
	mkdir -p ${dir $@}
	cat $< | scripts/split-devtest.pl -a -k \
	  --testset-dir ${dir $@} \
	  --devset-dir ${dir $@} \
	  --testfile $@ \
	  --devfile ${dir $@}dev-${TATOEBA_VERSION}.txt





${INFODIR}/%/overlap-with-test: ${RELEASEDIR}/%/train.id.gz
	mkdir -p ${dir $@}
	echo "# overlap with test set" > $@
	echo ""                       >> $@
	scripts/check-overlap.pl $(<:id.gz=src.gz) $(<:id.gz=trg.gz) \
		${dir $<}test.src  ${dir $<}test.trg >> $@

${INFODIR}/%/overlap-with-dev: ${RELEASEDIR}/%/train.id.gz
	echo "# overlap with dev set" >> $@
	echo ""                       >> $@
	scripts/check-overlap.pl $(<:id.gz=src.gz) $(<:id.gz=trg.gz) \
		${dir $<}dev.src  ${dir $<}dev.trg >> $@



## list all langids used in all data sets
## (also diff between devtest and train)

${INFODIR}/%/langids: ${RELEASEDIR}/%/train.id.gz
	echo -n "train source	" >> $@
	zcat $< | cut -f2 | sort -u | tr "\n" ' ' | sed 's/ *$$//' >> $@
	echo ""                   >> $@
	echo -n "train target	" >> $@
	zcat $< | cut -f3 | sort -u | tr "\n" ' ' | sed 's/ *$$//' >> $@
	echo ""                   >> $@
	if [ -e ${patsubst ${RELEASEDIR}/%/train.id.gz,${RELEASEDIR}/%/test.id,$<} ]; then \
	  echo -n "test source	" >> $@; \
	  cat ${patsubst ${RELEASEDIR}/%/train.id.gz,${RELEASEDIR}/%/test.id,$<} | \
		cut -f1 | sort -u | tr "\n" ' ' | sed 's/ *$$//' >> $@; \
	  echo ""                 >> $@; \
	  echo -n "test target	" >> $@; \
	  cat ${patsubst ${RELEASEDIR}/%/train.id.gz,${RELEASEDIR}/%/test.id,$<} | \
		cut -f2 | sort -u | tr "\n" ' ' | sed 's/ *$$//' >> $@; \
	  echo ""                 >> $@; \
	fi
	if [ -e ${patsubst ${RELEASEDIR}/%/train.id.gz,${RELEASEDIR}/%/dev.id,$<} ]; then \
	  echo -n "dev source	" >> $@; \
	  cat ${patsubst ${RELEASEDIR}/%/train.id.gz,${RELEASEDIR}/%/dev.id,$<} | \
		cut -f1 | sort -u | tr "\n" ' ' | sed 's/ *$$//' >> $@; \
	  echo ""                 >> $@; \
	  echo -n "dev target	" >> $@; \
	  cat ${patsubst ${RELEASEDIR}/%/train.id.gz,${RELEASEDIR}/%/dev.id,$<} | \
		cut -f2 | sort -u | tr "\n" ' ' | sed 's/ *$$//' >> $@; \
	  echo ""                 >> $@; \
	fi
	grep -v 'train source' $@ | grep source | cut -f2 | tr ' ' "\n" | sort -u > $@.srctest
	grep -v 'train target' $@ | grep target | cut -f2 | tr ' ' "\n" | sort -u > $@.trgtest
	grep 'train source' $@ | cut -f2 | tr ' ' "\n" > $@.srctrain
	grep 'train target' $@ | cut -f2 | tr ' ' "\n" > $@.trgtrain
	echo -n 'comm source	' >> $@
	comm -1 -2 $@.srctest $@.srctrain | tr "\n" ' ' | sed 's/ *$$//' >> $@
	echo ""                   >> $@
	echo -n 'comm target	' >> $@
	comm -1 -2 $@.trgtest $@.trgtrain | tr "\n" ' ' | sed 's/ *$$//' >> $@
	echo ""                   >> $@
	echo -n 'devtestonly source	' >> $@
	comm -2 -3 $@.srctest $@.srctrain | tr "\n" ' ' | sed 's/ *$$//' >> $@
	echo ""                   >> $@
	echo -n 'devtestonly target	' >> $@
	comm -2 -3 $@.trgtest $@.trgtrain | tr "\n" ' ' | sed 's/ *$$//' >> $@
	echo ""                   >> $@
	echo -n 'trainonly source	' >> $@
	comm -1 -3 $@.srctest $@.srctrain | tr "\n" ' ' | sed 's/ *$$//' >> $@
	echo ""                   >> $@
	echo -n 'trainonly target	' >> $@
	comm -1 -3 $@.trgtest $@.trgtrain | tr "\n" ' ' | sed 's/ *$$//' >> $@
	echo ""                   >> $@
	rm -f $@.srctest $@.srctrain $@.trgtest $@.trgtrain



## tab-separated versions of test and dev data (for github and downloads)

${TEST_TSV}: ${DATADIR}/test/%/test.txt: ${RELEASEDIR}/%/test.id
	mkdir -p ${dir $@}
	paste $< ${<:.id=.src} ${<:.id=.trg} > $@

${DEV_TSV}: ${DATADIR}/dev/%/dev.txt: ${RELEASEDIR}/%/dev.id
	mkdir -p ${dir $@}
	paste $< ${<:.id=.src} ${<:.id=.trg} > $@


wikidocs: ${WIKI_DOCS}

${WIKI_DOCS}:
	mkdir -p ${dir $@}
	( w=$(patsubst %.id.gz,%,${notdir $@}); \
	  if [ $$w == wikipedia ]; then w=wiki; fi; \
	  for l in ${shell ${SCRIPTDIR}/find_opus_langs.pl \
			${patsubst ${RELEASEDIR}/%/,%,${dir $@}} \
			${WIKI_LANGS}}; do \
	    echo "get wikidata for $$l"; \
	    if [ -e ${OPUSMT_WIKIDIR}/$$l/$$w.$$l.gz ]; then \
	      ${ZCAT} ${OPUSMT_WIKIDIR}/$$l/$$w.$$l.gz | langscript -3 -l $$l -r -D >> $@.tmpids; \
	      ${ZCAT} ${OPUSMT_WIKIDIR}/$$l/$$w.$$l.gz >> $@.tmptxt; \
	    fi \
	  done )
	if [ -e $@.tmptxt ]; then \
	  gzip -c < $@.tmptxt > $(@:.id.gz=.txt.gz); \
	  gzip -c < $@.tmpids > $@; \
	  rm -f $@.tmptxt $@.tmpids; \
	fi

BT_CONTAINER = https://object.pouta.csc.fi/Tatoeba-MT-bt

Backtranslations.md:
	echo "# Translated monolingual data" > $@
	echo "" >> $@
	echo "Automatically translated data sets that can be used for data augmentation" >> $@
	echo "Translations have been done with models trained on the Tatoeba MT challenge data." >> $@
	echo "We include translations of Wikipedia, WikiSource, WikiBooks, WikiNews and WikiQuote" >> $@
	echo "(if available for the source language we translate from)." >> $@
	echo "Translations are done on shuffled, de-duplicated data sets and they come in blocks " >> $@
	echo "of at most one million sentences per file." >> $@
	echo "" >> $@
	echo "| Size (sentences) | language pair | source | translation | MT model |" >> $@
	echo "|:-----------------|:-------------:|:-------|:------------|:--------:|" >> $@
	wget -qq -O - ${BT_CONTAINER}/released-data-size.txt | sort -k2,2 | grep -v '^[0-9]	' |\
	perl -e 'use File::Basename;while (<>){chomp;@a=split(/\t/);if ($$#a==2){($$lang)=split(/\//,$$a[1]);$$f1 = basename($$a[1]);$$f2 = basename($$a[2]);$$d1 = dirname($$a[1]);$$d2 = dirname($$a[2]);print "| $$a[0] | $$lang | [$$f1](${BT_CONTAINER}/$$a[1]) | [$$f2](${BT_CONTAINER}/$$a[2]) | [info](${BT_CONTAINER}/$$d1/README.md) |\n";}}' >> $@



## make a copy of the latest statistics
Data.md: Data-${VERSION}.md
	cp $< $@

## statistics of the data sets
${STATISTICS}:
	mkdir -p $(dir $@)
	echo "# Tatoeba Challenge Data - ${VERSION}" > $@
	echo "" >> $@
	echo "| lang-pair |    test    |    dev     |    train   |" >> $@
	echo "|-----------|------------|------------|------------|" >> $@
	for l in ${TATOEBA_PAIRS3}; do \
	  if [ -s ${RELEASEDIR}/$$l/test.id ] || [ -e ${RELEASEDIR}/$$l/train.id.gz ]; then \
	  echo -n "| " >> $@; \
	  echo "$$l" | sed 's/-/ /' | xargs ${ISO639} | \
		sed 's/" "/ - /' | awk '{printf "%30s\n", $$0}' | tr "\"\n" '  ' >> $@; \
	  echo -n "[$$l](${DOWNLOADURL}/${RELEASE_CONTAINER}/$$l.tar)  | " >> $@; \
	  if [ -e ${RELEASEDIR}/$$l/test.id ]; then \
	    cat ${RELEASEDIR}/$$l/test.id | wc -l | awk '{printf "%10s", $$0}' >> $@; \
	  else \
	    echo -n "           " >> $@; \
	  fi; \
	  echo -n "| " >> $@; \
	  if [ -e ${RELEASEDIR}/$$l/dev.id ]; then \
	    cat ${RELEASEDIR}/$$l/dev.id | wc -l | awk '{printf "%10s", $$0}' >> $@; \
	  else \
	    echo -n "           " >> $@; \
	  fi; \
	  echo -n "| " >> $@; \
	  if [ -e ${RELEASEDIR}/$$l/train.id.gz ]; then \
	    ${GZIP} -cd < ${RELEASEDIR}/$$l/train.id.gz | wc -l | awk '{printf "%10s", $$0}' >> $@; \
	    echo "|" >> $@; \
	  else \
	    echo "           |" >> $@; \
	  fi; \
	  fi \
	done


## extended statistics with word counts
Statisics-${VERSION}.md:
	echo "# Tatoeba Challenge Data" > $@
	echo "" >> $@
	echo "| lang-pair |    test    |    dev     |    train   |  train-src |  train-trg |" >> $@
	echo "|-----------|------------|------------|------------|------------|------------|" >> $@
	for l in ${TATOEBA_PAIRS3}; do \
	  if [ -s ${RELEASEDIR}/$$l/test.id ] || [ -e ${RELEASEDIR}/$$l/train.id.gz ]; then \
	  echo -n "|  $$l  | " >> $@; \
	  cat ${RELEASEDIR}/$$l/test.id | wc -l | awk '{printf "%10s\n", $$0}' | tr "\n" ' ' >> $@; \
	  echo -n "| " >> $@; \
	  if [ -e ${RELEASEDIR}/$$l/dev.id ]; then \
	    cat ${RELEASEDIR}/$$l/dev.id | wc -l | awk '{printf "%10s\n", $$0}' | tr "\n" ' ' >> $@; \
	  else \
	    echo -n "           " >> $@; \
	  fi; \
	  echo -n "| " >> $@; \
	  if [ -e ${RELEASEDIR}/$$l/train.id.gz ]; then \
	    ${GZIP} -cd < ${RELEASEDIR}/$$l/train.id.gz | wc -l | awk '{printf "%10s\n", $$0}' | tr "\n" ' ' >> $@; \
	    echo -n "| " >> $@; \
	    ${GZIP} -cd < ${RELEASEDIR}/$$l/train.src.gz | wc -w | awk '{printf "%10s\n", $$0}' | tr "\n" ' ' >> $@; \
	    echo -n "| " >> $@; \
	    ${GZIP} -cd < ${RELEASEDIR}/$$l/train.trg.gz | wc -w | awk '{printf "%10s\n", $$0}' | tr "\n" ' ' >> $@; \
	    echo "|" >> $@; \
	  else \
	    echo "           |            |            |" >> $@; \
	    echo "           |" >> $@; \
	  fi; \
	  fi \
	done

TATOEBA_WIKIDOC_URL      := ${DOWNLOADURL}/${WIKIDOC_CONTAINER}
TATOEBA_WIKISHUFFLED_URL := ${DOWNLOADURL}/${WIKISHUF_CONTAINER}

Wiki.md: Wiki-${VERSION}.md

Wiki-${VERSION}.md:
	echo "# Tatoeba Challenge Data - Wikimedia data" > $@
	echo "" >> $@
	echo "This is part of the "                     >> $@
	echo "[Tatoeba Translation Challenge Data set](https://github.com/Helsinki-NLP/Tatoeba-Challenge)." >> $@
	echo "The following monolingual data sets are extracted from"                                       >> $@
	echo "[CirrusSearch Wikimedia dumps](https://dumps.wikimedia.org/other/cirrussearch/)"              >> $@
	echo "including:"                               >> $@
	echo "* Wikipedia"                              >> $@
	echo "* Wikibooks"                              >> $@
	echo "* Wikinews"                               >> $@
	echo "* Wikiquote"                              >> $@
	echo "* Wikisource"                             >> $@
	echo "" >> $@
	echo "All data sets are in UTF8 plain text,"                           >> $@
	echo "one sentence per line."                                          >> $@
	echo "We provide a deduplicated shuffled download"                     >> $@
	echo "and a complete download with document boundaries (empty lines)." >> $@
	echo "Simple pre-processing like unicode character normalisation "     >> $@
	echo "and language-identification-based filtering has been applied"    >> $@
	echo "to reduce some noise. The extraction scripts are part of"        >> $@
	echo "[OPUS-MT](https://github.com/Helsinki-NLP/OPUS-MT-train)."       >> $@
	echo "" >> $@
	for l in ${sort ${notdir ${wildcard wiki-shuffled/???}}}; do \
	  echo -n "* [$$l shuffled](${TATOEBA_WIKISHUFFLED_URL}/$$l.tar)" >> $@; \
	  if [ -e wiki-doc/$$l ]; then \
	    echo -n ", [$$l documents](${TATOEBA_WIKIDOC_URL}/$$l.tar)"   >> $@; \
	  fi; \
	  echo "" >> $@; \
	done


MonolingualData.md: MonolingualData-${VERSION}.md

MonolingualData-${VERSION}.md:
	echo "# Tatoeba Challenge Data - Monolingual data sets - ${VERSION}" > $@
	echo "" >> $@
	echo "This is part of the "                     >> $@
	echo "[Tatoeba Translation Challenge Data set](https://github.com/Helsinki-NLP/Tatoeba-Challenge)." >> $@
	echo "The following monolingual data sets are extracted from"                                       >> $@
	echo "[CirrusSearch Wikimedia dumps](https://dumps.wikimedia.org/other/cirrussearch/)"              >> $@
	echo "including:"                               >> $@
	echo "* Wikipedia"                              >> $@
	echo "* Wikibooks"                              >> $@
	echo "* Wikinews"                               >> $@
	echo "* Wikiquote"                              >> $@
	echo "* Wikisource"                             >> $@
	echo "" >> $@
	echo "All data sets are in UTF8 plain text, one sentence"           >> $@
	echo "per line and document boundaries (empty lines)."              >> $@
	echo "" >> $@
	echo "The packages below use the same division into languages"      >> $@
	echo "and macro-languages as they are defined in the Tatoeba"       >> $@
	echo "translation challenge. Language ID files with script"         >> $@
	echo "information are also added to each data source in the "       >> $@
	echo "same way as it is done for the bilingual data sets."          >> $@
	echo "" >> $@
	echo "There are also packages with the original Wikipedia"          >> $@
	echo "languages (converted to ISO-639-3) that you can"              >> $@
	echo "download in a deduplicated and shuffled version"              >> $@
	echo "or with document boundaries from [this page](Wiki.md)"        >> $@
	echo "" >> $@
	echo "Simple pre-processing like unicode character normalisation "  >> $@
	echo "and language-identification-based filtering has been applied" >> $@
	echo "to reduce some noise. The extraction scripts are part of"     >> $@
	echo "[OPUS-MT](https://github.com/Helsinki-NLP/OPUS-MT-train)."    >> $@
	echo "" >> $@
	for l in ${WIKI_LANGS3}; do \
	  echo -n "* [$$l](${DOWNLOADURL}/${RELEASE_CONTAINER}/$$l.tar)"   >> $@; \
	  echo "" >> $@; \
	done




.PHONY: subsets
subsets: subsets/insufficient.md \
	subsets/zero.md \
	subsets/lowest.md \
	subsets/lower.md \
	subsets/medium.md \
	subsets/higher.md \
	subsets/highest.md \
	subsets/LessThan1000.md


subsets/%.md: subsets/${VERSION}/%.md
	cp $< $@

subsets/${VERSION}/%.md: ${STATISTICS}
	mkdir -p ${dir $@}
	@echo "# Tatoeba Challenge Data - ${VERSION}" > $@
	@echo "" >> $@
	@echo "This is the \"${patsubst %.md,%,${notdir $@}}\" sub-set of the Tatoeba data." >> $@
	@echo "Download the data files from the link in the table below." >> $@
	@echo "There is a total of" >> $@
	@echo "" >> $@
	@echo -n "* " >> $@
	${SCRIPTDIR}/divide-data-sets.pl < $< |\
	grep '${patsubst %.md,%,${notdir $@}}' |\
	wc -l | tr "\n" ' ' >> $@
	@echo " language pairs in this sub-set" >> $@
	@echo "" >> $@
	@echo "| lang-pair |    test    |    dev     |    train   |" >> $@
	@echo "|-----------|------------|------------|------------|" >> $@
	${SCRIPTDIR}/divide-data-sets.pl < $< |\
	grep '${patsubst %.md,%,${notdir $@}}' |\
	sed 's/|[^|]*$$/|/' >> $@


${DATADIR}/relative-test-size.txt:
	wc -l  ${TESTDATADIR}/*eng*/test.txt | \
	grep -v total | \
	perl -e 'while(<>){@a=split(/\s+/);@b=split(/\//,$$a[-1]);$$b[2]=~s/\-?eng\-?//;print $$b[2]," ",$$a[1]/10000,"\n";}' > $@


${DATADIR}/relative-test-size-per-language.txt:
	cat ${TESTDATADIR}/eng-*/test.txt |\
	cut -f2 | \
	sed 's/est/ekk/' |\
	sed 's/kur_Arab/ckb/' |\
	sed 's/kur_Latn/kmr/' |\
	sed 's/grn/gug/' |\
	sed 's/\_[^ ]*//' |\
	sort | uniq -c |\
	sed 's/^ *//' |\
	awk '{print $$2 " " $$1/10000}' > $@




# TATOEBA_READMES = $(wildcard models/*/README.md)
TATOEBA_YAML = $(wildcard models/*/*.yml)

models/released-models.txt: ${TATOEBA_YAML}
	find models -name '*.yml' | \
	xargs scripts/get-model-scores.pl -t |\
	cut -f1,4,5                                            > $@.1
	cut -f1 -d'/' $@.1                                     > $@.iso639-3
	cut -f1 -d'/' $@.1 | \
	xargs iso639 -2 -k -p | tr ' ' "\n"                    > $@.iso639-1
	cut -f1 -d'/' $@.1 | \
	sed 's/^\([^ \-]*\)$$/\1-\1/g' | \
	tr '-' ' ' | \
	xargs iso639 -k | sed 's/$$/ /' |\
	sed -e 's/\" \"\([^\"]*\)\" /\t\1\n/g' | \
	sed 's/^\"//g'                                         > $@.langs
	cut -f1 $@.1 | \
	sed 's#^#${TATOEBA_MODELURL}/#'                        > $@.url
	cut -f2,3 $@.1                                         > $@.scores
	paste $@.url $@.iso639-3 $@.iso639-1 $@.scores $@.langs | grep zip > $@
	rm -f $@.url $@.iso639-3 $@.iso639-1 $@.scores $@.langs $@.1

models/released-model-results.txt: ${TATOEBA_YAML}
	find models -name '*.yml' | \
	xargs scripts/get-model-scores.pl -S -s 200 |\
	grep 'Tatoeba-test' | grep -v 'multi'          > $@.1 
	cut -f2 $@.1                                   > $@.langs
	cut -f1 $@.1 | sed 's#^#${TATOEBA_MODELURL}/#' > $@.url
	cut -f4,5 $@.1                                 > $@.scores
	cut -f6,7 $@.1                                 > $@.sizes
	paste $@.langs $@.scores $@.url $@.sizes | \
	sort -k1,1 -k3,3nr -k2,2nr -k4,4 | uniq | grep zip > $@
	rm -f $@.1 $@.langs $@.url $@.scores $@.sizes

models/released-model-results-all.txt: ${TATOEBA_YAML}
	find models -name '*.yml' | \
	xargs scripts/get-model-scores.pl -S |\
	grep 'Tatoeba-test' | grep -v 'multi'          > $@.1 
	cut -f2 $@.1                                   > $@.langs
	cut -f1 $@.1 | sed 's#^#${TATOEBA_MODELURL}/#' > $@.url
	cut -f4,5 $@.1                                 > $@.scores
	cut -f6,7 $@.1                                 > $@.sizes
	paste $@.langs $@.scores $@.url $@.sizes | \
	sort -k1,1 -k3,3nr -k2,2nr -k4,4 | uniq | grep zip > $@
	rm -f $@.1 $@.langs $@.url $@.scores $@.sizes

models/released-model-results-other.txt: ${TATOEBA_YAML}
	find models -name '*.yml' | \
	xargs scripts/get-model-scores.pl -S |\
	grep -v 'Tatoeba-test'                         > $@.1 
	cut -f2,3 $@.1                                 > $@.langs
	cut -f1 $@.1 | sed 's#^#${TATOEBA_MODELURL}/#' > $@.url
	cut -f4,5 $@.1                                 > $@.scores
	cut -f6,7 $@.1                                 > $@.sizes
	paste $@.langs $@.scores $@.url $@.sizes | \
	sort -k1,1 -k2,2 -k4,4nr -k3,3nr -k5,5 | uniq | grep zip > $@
	rm -f $@.1 $@.langs $@.url $@.scores $@.sizes


# models/released-models.txt: ${TATOEBA_READMES}
# #	-cat $@ > $@.${TODAY}
# 	find models/ -name '*.eval.txt' | sort | xargs grep chrF2 > $@.1
# 	find models/ -name '*.eval.txt' | sort | xargs grep BLEU > $@.2
# 	cut -f3 -d '/' $@.1 | sed 's/\.eval.txt.*$$/.zip/' > $@.zip
# 	cut -f2 -d '/' $@.1 > $@.iso639-3
# 	paste -d '/' $@.iso639-3 $@.zip | sed 's#^#${TATOEBA_MODELURL}/#' > $@.url
# 	cut -f2 -d '/' $@.1 | xargs iso639 -2 -k -p | tr ' ' "\n" > $@.iso639-1
# 	cut -f2 -d '=' $@.1 | cut -f2 -d ' ' > $@.chrF2
# 	cut -f2 -d '=' $@.2 | cut -f2 -d ' ' > $@.bleu
# 	cut -f3 -d '=' $@.2 | cut -f2 -d ' ' > $@.bp
# 	cut -f6 -d '=' $@.2 | cut -f2 -d ' ' | cut -f1 -d')' > $@.reflen
# 	cut -f2 -d '/' $@.1 | sed 's/^\([^ \-]*\)$$/\1-\1/g' | tr '-' ' ' | \
# 	xargs iso639 -k | sed 's/$$/ /' |\
# 	sed -e 's/\" \"\([^\"]*\)\" /\t\1\n/g' | sed 's/^\"//g' > $@.langs
# 	paste $@.url $@.iso639-3 $@.iso639-1 $@.chrF2 $@.bleu $@.bp $@.reflen $@.langs > $@.new
# 	rm -f $@.url $@.iso639-3 $@.iso639-1 $@.chrF2 $@.bleu $@.bp $@.reflen $@.1 $@.2 $@.langs $@.zip
# 	cat $@.${TODAY} $@.new | sort | uniq | grep zip |\
# 	scripts/check-model-availability.pl models/available-models.txt 2> $@.log > $@
# 	rm -f $@.new


# models/released-model-languages.txt: ${TATOEBA_READMES}
# 	-cat $@ > $@.${TODAY}
# 	find models/ -name 'README.md' | sort | \
# 	xargs egrep -h '^(# |\* source language|\* target language|\* download:)' |\
# 	tr "\t" " " | tr "\n" "\t" | sed "s/# /\n# /g" > $@.1
# 	grep -o '\* download: [^ ]*)' $@.1 | cut -f2 -d\( | sed 's/)//' > $@.url
# 	grep -o '# [^ ]*	'  $@.1 | sed 's/^# *//' > $@.model
# 	grep -o '\* source language(s): [^	]*	' $@.1 | \
# 		cut -f2 -d: | cut -f1 | sed 's/^ *//' > $@.src
# 	grep -o '\* target language(s): [^	]*	' $@.1 | \
# 		cut -f2 -d: | cut -f1 | sed 's/^ *//' > $@.trg
# 	cut -f5 -d/ $@.url > $@.iso639-3
# 	cut -f5 -d/ $@.url | xargs iso639 -2 -k -p | tr ' ' "\n" > $@.iso639-1
# 	cut -f5 -d/ $@.url | sed 's/^\([^ \-]*\)$$/\1-\1/g' | tr '-' ' ' | \
# 	xargs iso639 -k | sed 's/$$/ /' |\
# 	sed -e 's/\" \"\([^\"]*\)\" /\t\1\n/g' | sed 's/^\"//g' > $@.langs
# 	paste $@.url $@.iso639-3 $@.iso639-1 $@.langs $@.src $@.trg > $@.new
# 	rm -f $@.1 $@.url $@.iso639-3 $@.iso639-1 $@.langs $@.src $@.trg
# 	cat $@.${TODAY} $@.new | sort | uniq | grep zip |\
# 	scripts/check-model-availability.pl models/available-models.txt 2> $@.log > $@
# 	rm -f $@.new

# models/released-model-results.txt: ${TATOEBA_READMES}
# 	-cat $@ > $@.${TODAY}
# 	find models/ -name 'README.md' | sort | \
# 	xargs egrep -h '^(# |\| Tatoeba-test|\* download:)' |\
# 	tr "\t" " " | tr "\n" "\t" | sed "s/# /\n# /g" |\
# 	perl -e 'while (<>){s/^.*\((.*)\)/\1/;@_=split(/\t/);$$m=shift(@_);for (@_){print "$$_\t$$m\n";}}' |\
# 	grep -v '.multi.' |\
# 	sed -e 's/Tatoeba-test.\S*\(...\....\) /\1/' |\
# 	grep '^|' |\
# 	sed -e 's/ *| */\t/g' | cut -f2,3,4,6 > $@.new
# 	cat $@.${TODAY} $@.new | sort -k1,1 -k3,3nr -k2,2nr -k4,4 | uniq | grep zip |\
# 	scripts/check-model-availability.pl models/available-models.txt 2> $@.log > $@
# 	rm -f $@.new



# RESULT_TABLE_HEADER=model\tlanguage-pair\ttestset\tchrF2\tBLEU\tBP\treference-length\n--------------------------------------------------------------------------\n
RESULT_TABLE_HEADER=model\tlanguage-pair\ttestset\tchrF2\tBLEU\n--------------------------------------------------------------------------\n

${RESULT_FILES}: results/%.md: %
	mkdir -p ${dir $@}
	echo "# Tatoeba translation results" >$@
	echo "" >>$@
	echo "Note that some links to the actual models below are broken"                  >> $@
	echo "because the models are not yet released or their performance is too poor"    >> $@
	echo "to be useful for anything."                                                  >> $@
	echo ""                                                                            >> $@
#	echo '| Model | Test Set | chrF2 | BLEU | BP | Reference Length |' >> $@
#	echo '|:--|---|--:|--:|--:|--:|'                                                   >> $@
	echo '| Model | Test Set | chrF2 | BLEU |'                                         >> $@
	echo '|:--|---|--:|--:|'                                                           >> $@
	grep -v '^model' $< | grep -v -- '----' | grep . | \
		sort -k2,2 -k3,3 -k4,4nr | sort -k2,2 -k3,3 -k 1,1 -u | sort -k2,2 -k3,3 -k4,4nr |\
	perl -pe '@a=split;print "| lang = $$a[1] | | | |\n" if ($$b ne $$a[1]);$$b=$$a[1];' |\
	cut -f1,3- |\
	perl -pe '/^(\S*)\/(\S*)\t/;if (-d "models/$$1"){s/^(\S*)\/(\S*)\t/[$$1\/$$2](..\/models\/$$1)\t/;}' |\
	sed 's/	/ | /g;s/^/| /;s/$$/ |/;s/Tatoeba-test/tatoeba/' |\
	sed 's/\(news[^ ]*\)-...... /\1 /;s/\(news[^ ]*\)-.... /\1 /;'                     >> $@



## TODO:  should check available models
##        in ObjectStore instead of local file directories!

results/tatoeba-models-all.md: tatoeba-models-all
	mkdir -p ${dir $@}
	echo "# Tatoeba translation models" >$@
	echo "" >>$@
	echo "The scores refer to results on Tatoeba-test data"                            >> $@
	echo "For multilingual models, it is a mix of all language pairs"                  >> $@
	echo ""                                                                            >> $@
	echo '| Model | chrF2 | BLEU |'                                                    >> $@
	echo '|:--|--:|--:|'                                                               >> $@
	cut -f1,4- $< | \
	perl -pe '/^(\S*)\/(\S*)\t/;if (-d "models/$$1"){s/^(\S*)\/(\S*)\t/[$$1\/$$2](..\/models\/$$1)\t/;}' |\
	sed 's/	/ | /g;s/^/| /;s/$$/ |/'                                                   >> $@



## new: also consider the opposite translation direction!
tatoeba-results-all-subset-%: tatoeba-results-all-sorted-langpair
	${MAKE} ${patsubst tatoeba-results-all-subset-%,subsets/%.md,$@}
	( l="${shell grep '\[' ${patsubst tatoeba-results-all-subset-%,subsets/%.md,$@} | \
		cut -f2 -d '[' | cut -f1 -d ']' | \
		sort -u  | tr "\n" '|' | sed 's/|$$//;s/\-/\\\-/g'}"; \
	  r="${shell grep '\[' ${patsubst tatoeba-results-all-subset-%,subsets/%.md,$@} | \
		cut -f2 -d '[' | cut -f1 -d ']' | \
		sort -u  | sed 's/\(...\)-\(...\)/\2-\1/' | tr "\n" '|' | sed 's/|$$//;s/\-/\\\-/g'}"; \
	  grep -P "$$l|$$r" $< |\
	  perl -pe '@a=split;print "\n${RESULT_TABLE_HEADER}" if ($$b ne $$a[1]);$$b=$$a[1];' > $@ )



## get the latest results from OPUS-MT

OPUS_MT_RAW = https://raw.githubusercontent.com/Helsinki-NLP/OPUS-MT-train/master/

tatoeba-results-all: ${TATOEBA_YAML}
	find models -name '*.yml' | \
	xargs scripts/get-model-scores.pl -s 200 |\
	sed 's/-....-..-..\.zip//' |\
	sort -r | sort -k1,1 -k2,2 -k3,3 -k4,4nr -k5,5nr -u > $@

#	wget -O $@-work ${OPUS_MT_RAW}/work-tatoeba/$@
#	cut -f4 $< | cut -f5,6 -d'/' | sed 's/-....-..-..\.zip$$//' > $@.1
#	cut -f1 $< | tr '.' '-' > $@.2
#	cut -f4 $< | cut -f4 -d'/' > $@.3
#	cut -f3 $< > $@.4
#	cut -f2 $< > $@.5
#	paste $@.1 $@.2 $@.3 $@.4 $@.5 | sed 's/Tatoeba-MT-models/Tatoeba-test/' >> $@-work
#	sort -r $@-work | sort -k1,1 -k2,2 -k3,3 -k4,4nr -k5,5nr -u > $@
#	rm -f $@.1 $@.2 $@.3 $@.4 $@.5 $@-work


tatoeba-models-all: ${TATOEBA_YAML}
	find models -name '*.yml' | \
	xargs scripts/get-model-scores.pl -t |\
	sed 's/-....-..-..\.zip//' |\
	sort -r | sort -k1,1 -k2,2 -k3,3 -k4,4nr -k5,5nr -u > $@


tatoeba-results-all-sorted-langpair: tatoeba-results-all
	sort -k2,2 -k3,3 -k4,4nr < $< |\
	perl -pe '@a=split;print "\n${RESULT_TABLE_HEADER}" if ($$b ne $$a[1]);$$b=$$a[1];' \
	> $@

tatoeba-results-all-sorted-chrf2: tatoeba-results-all
	sort -k3,3 -k4,4nr < $< > $@

tatoeba-results-all-sorted-bleu: tatoeba-results-all
	sort -k3,3 -k5,5nr < $< > $@


cleanup-model-dirs:
	which a-put
	for d in `find models -maxdepth 1 -mindepth 1 -type d`; do \
	  echo "check $$d"; \
	  scripts/cleanup-model-releases.pl -r models/available-models.txt $$d; \
	done
	swift list Tatoeba-MT-models > models/available-models.txt


## upload data to ObjectStorage on allas
## - requires a-tools!
##
##   module load allas
##   allas-conf


CSC_PROJECT = project_2003093
APUT_FLAGS = -p ${CSC_PROJECT} --override --nc --skip-filelist

## released train/dev/test data
${RELEASEDIR}/%.done: ${RELEASEDIR}/%
	a-put ${APUT_FLAGS} -b ${RELEASE_CONTAINER} $<
	touch $@

## incremental data sets
${DEVTESTDIR}.done: ${DEVTESTDIR}
	a-put ${APUT_FLAGS} -b ${TATOEBA_CONTAINER} $<
	touch $@


# ## released test sets
# ${TESTDATADIR}-${VERSION}.done: ${TESTDATADIR}
# 	a-put ${APUT_FLAGS} -b ${TATOEBA_CONTAINER} -o test-${VERSION} $<
# 	touch $@

# ## released dev sets
# ${DEVDATADIR}-${VERSION}.done: ${DEVDATADIR}
# 	a-put ${APUT_FLAGS} -b ${TATOEBA_CONTAINER} -o dev-${VERSION} $<
# 	touch $@






## size of each test set
${TESTDATADIR}-${VERSION}.size: ${TESTDATADIR}
	find $< -name 'test.txt' -exec wc -l {} \; > $@

## subset of test sets that are larger than 200 sentences
${TESTDATADIR}-${VERSION}: ${TESTDATADIR}-${VERSION}.size
	mkdir -p ${dir $@}
	egrep '[0-9]{4,}' $< | cut -f2 -d' '  > $@.selected
	egrep '[2-9]{3}'  $< | cut -f2 -d' ' >> $@.selected
	tar -T $@.selected --transform 's,^${TESTDATADIR},${TESTDATADIR}-${VERSION},' -cf $@.tar
	tar -xf $@.tar
	rm -f $@.tar

## released test sets
${TESTDATADIR}-${VERSION}.done: ${TESTDATADIR}-${VERSION}
	a-put ${APUT_FLAGS} -b ${TATOEBA_CONTAINER} $<
	touch $@



## size of each test set
${DEVDATADIR}-${VERSION}.size: ${DEVDATADIR}
	find $< -name 'dev.txt' -exec wc -l {} \; > $@

## subset of test sets that are larger than 200 sentences
${DEVDATADIR}-${VERSION}: ${DEVDATADIR}-${VERSION}.size
	mkdir -p ${dir $@}
	egrep '[0-9]{4,}' $< | cut -f2 -d' '  > $@.selected
	egrep '[2-9]{3}'  $< | cut -f2 -d' ' >> $@.selected
	tar -T $@.selected --transform 's,^${DEVDATADIR},${DEVDATADIR}-${VERSION},' -cf $@.tar
	tar -xf $@.tar
	rm -f $@.tar

## released test sets
${DEVDATADIR}-${VERSION}.done: ${DEVDATADIR}-${VERSION}
	a-put ${APUT_FLAGS} -b ${TATOEBA_CONTAINER} $<
	touch $@





## upload wiki-data

${RELEASEDIR}/wiki-shuffled-%.done: wiki-shuffled/%
	mkdir -p ${TMPDIR}/wiki-shuffled
	cp -R -L $< ${TMPDIR}/wiki-shuffled/
	cd ${TMPDIR}/wiki-shuffled/ && a-put ${APUT_FLAGS} -b Tatoeba-Challenge-WikiShuffled ${notdir $<}
	rm -f ${TMPDIR}/$</*
	rmdir ${TMPDIR}/$<
	touch $@

${RELEASEDIR}/wiki-doc-%.done: wiki-doc/%
	mkdir -p ${TMPDIR}/wiki-doc
	cp -R -L $< ${TMPDIR}/wiki-doc/
	cd ${TMPDIR}/wiki-doc/ && a-put ${APUT_FLAGS} -b Tatoeba-Challenge-WikiDoc ${notdir $<}
	rm -f ${TMPDIR}/$</*
	rmdir ${TMPDIR}/$<
	touch $@





CSCPROJECT  ?= project_2003093

HPC_QUEUE   ?= small
HPC_MEM     ?= 32g
HPC_CORES   ?= 8
HPC_DISK    ?= 500
HPC_NODES   ?= 1
HPC_TIME    ?= 72:00

%.submit:
	echo '#!/bin/bash -l' > $@
	echo '#SBATCH -J "${@:.submit=}"' >>$@
	echo '#SBATCH -o ${@:.submit=}.out.%j' >> $@
	echo '#SBATCH -e ${@:.submit=}.err.%j' >> $@
	echo '#SBATCH --mem=${HPC_MEM}' >> $@
ifdef EMAIL
	echo '#SBATCH --mail-type=END' >> $@
	echo '#SBATCH --mail-user=${EMAIL}' >> $@
endif
ifeq (${shell hostname --domain 2>/dev/null},bullx)
	echo '#SBATCH --account=${CSCPROJECT}' >> $@
	echo '#SBATCH --gres=nvme:${HPC_DISK}' >> $@
endif
	echo '#SBATCH -n ${HPC_CORES}' >> $@
	echo '#SBATCH -N ${HPC_NODES}' >> $@
	echo '#SBATCH -p ${HPC_QUEUE}' >> $@
	echo '#SBATCH -t ${HPC_TIME}:00' >> $@
	echo '${HPC_EXTRA}' >> $@
	echo 'module use -a /proj/nlpl/modules' >> $@
	for m in ${CPU_MODULES}; do \
	  echo "module load $$m" >> $@; \
	done
	echo 'module list' >> $@
	echo 'cd $${SLURM_SUBMIT_DIR:-.}' >> $@
	echo 'pwd' >> $@
	echo 'echo "Starting at `date`"' >> $@
	echo '${MAKE} -j ${HPC_CORES} ${MAKEARGS} ${@:.submit=}' >> $@
	echo 'echo "Finishing at `date`"' >> $@
	sbatch $@



## some auxiliary functions

print-additional-opuslangs:
	@echo "nr of additional language pairs: $(words ${EXTRA_OPUS_PAIRS3})"
	@echo "${EXTRA_OPUS_PAIRS3}"
#	@echo "${EXTRA_OPUS_LANGS3}"
#	@echo "${EXTRA_TRAIN_DATA}"



print-languages:
	@echo "${TATOEBA_LANGS3}"

print-langpairs:
	@echo "${TATOEBA_PAIRS3}"

nonstandard-codes:
	@${ISO639} -n -m ${OPUS_LANGS} | tr ' ' "\n" > $@.isoopus
	@${ISO639} -n -m -k ${OPUS_LANGS} | tr ' ' "\n" > $@.allopus

nonstandard-tatoeba:
	@${GET_ISO_CODE} -n -k ${TATOEBA_LANGS} | tr ' ' "\n" > $@.all
	@${GET_ISO_CODE} -n ${TATOEBA_LANGS} | tr ' ' "\n" > $@.iso

move-diff-langpairs:
	@echo ${filter-out ${TATOEBA_PAIRS3},${shell ls ${RELEASEDIR}}}
	mkdir -p data-wrong
	for d in ${filter-out ${TATOEBA_PAIRS3},${shell ls ${RELEASEDIR}}}; do \
	  mv ${RELEASEDIR}/$$d data-wrong/; \
	done



copy-old-testsets:
	for p in ${TATOEBA_PAIRS3}; do \
	  if [ -e ${RELEASEDIR}/$$p/test.id ]; then \
	    mkdir -p ${DEVTESTDIR}/$$p; \
	    paste ${RELEASEDIR}/$$p/test.id ${RELEASEDIR}/$$p/test.src ${RELEASEDIR}/$$p/test.trg > ${DEVTESTDIR}/$$p/test-v2020-05-31.txt; \
	  fi; \
	  if [ -e ${RELEASEDIR}/$$p/dev.id ]; then \
	    mkdir -p ${DEVTESTDIR}/$$p; \
	    paste ${RELEASEDIR}/$$p/dev.id ${RELEASEDIR}/$$p/dev.src ${RELEASEDIR}/$$p/dev.trg > ${DEVTESTDIR}/$$p/dev-v2020-05-31.txt; \
	  fi; \
	done





############# huggingface integration #######################

MODELS ?= heb-ita ita-heb fra-heb heb-fra
MODEL  ?= ${firstword ${MODELS}}

CONVERTED_MODELS ?= ${notdir ${wildcard transformers/converted/*}}
CONVERTED_MODEL  ?= ${firstword ${CONVERTED_MODELS}}
RENAMED_MODEL     = ${patsubst opus-mt-%,opus-tatoeba-%,${CONVERTED_MODEL}}

huggingface-convert: transformers/${MODEL}.converted
huggingface-commit: transformers/${CONVERTED_MODEL}.committed

huggingface-convert-all:
	for m in ${MODELS}; do \
	  ${MAKE} MODEL=$$m huggingface-convert; \
	done

huggingface-commit-all:
	for m in ${CONVERTED_MODELS}; do \
	  ${MAKE} CONVERTED_MODEL=$$m huggingface-commit; \
	done


transformers:
	git clone git@github.com:huggingface/transformers.git
	cd transformers
	pip install -e --user .
	pip install --user pandas
	pip install --user -r examples/requirements.txt
	curl https://cdn-datasets.huggingface.co/language_codes/language-codes-3b2.csv  > language-codes-3b2.csv
	curl https://cdn-datasets.huggingface.co/language_codes/iso-639-3.csv > iso-639-3.csv
	-apt-get install git-lfs


transformers/Tatoeba-Challenge: transformers
	ln -s `pwd` $@

${HOME}/.huggingface/token: # transformers
	transformers-cli login

transformers/${MODEL}.converted: transformers
	cd transformers && \
	python src/transformers/models/marian/convert_marian_tatoeba_to_pytorch.py --models ${MODEL} --save_dir converted
	touch $@

ifneq (${CONVERTED_MODEL},)
transformers/${CONVERTED_MODEL}.committed: transformers/converted/${CONVERTED_MODEL} ${HOME}/.huggingface/token
	-transformers-cli repo create ${RENAMED_MODEL} \
		--organization Helsinki-NLP
	-git clone https://tiedeman:`cat ${HOME}/.huggingface/token`@huggingface.co/Helsinki-NLP/${RENAMED_MODEL}
	cd ${RENAMED_MODEL} && git lfs install
	cd ${RENAMED_MODEL} && git config --global user.email "jorg.tiedemann@helsinki.fi"
	cd ${RENAMED_MODEL} && git config --global user.name "Joerg Tiedemann"
	mv  $</* ${RENAMED_MODEL}/
	cd ${RENAMED_MODEL} && git add .
	cd ${RENAMED_MODEL} && git commit -m "Initial commit"
	cd ${RENAMED_MODEL} && git push
	rm -fr $<
	touch $@
endif
