#!/bin/bash
# Script to run VCF_darwindow_region in parallel for all vcf subset files generated with BAM2VCF script.
# The script will create subdirectories named Darwindow_mybed1, Darwindow_mybed2, etc.

# Expects to find in the working directory two types of files:
# - mybed1.txt 
# - PREFIX.globalfilter.thin0.mybed1.txt.vcf.gz

#####################################################

VCFPREFIX=Roe71		# IMPORTANT!! Define prefix here.

#####################################################


INPUTDIR=$(pwd)
ls -1 mybed*txt > mybedfiles.txt

for mybedfile in $(cat mybedfiles.txt) 
	do
	echo $mybedfile
	bn=$(basename $mybedfile .txt)
    	mydir="Darwindow_${bn}"
	mkdir -p $mydir
    	cp VCF_darwindow_region.sh ${mydir}/
    	(cd $mydir && ./VCF_darwindow_region.sh $mybedfile $VCFPREFIX $INPUTDIR &)
	done

