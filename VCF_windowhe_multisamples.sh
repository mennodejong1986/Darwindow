#!/bin/bash
# script to calculate sample heterozygosity on a sliding window basis
# requires tabix (both bgzip and tabix itself)
# in case you would like to double check the outcome, the weighted mean should be equal to PSC section in output file generated by the command:
# /opt/software/bcftools/bcftools-1.9/bin/bcftools stats -s - --threads 10 myinput.vcf.gz > myinput.bcfstats.txt &


# This script expects a vcf file as input, either gzipped or unzipped.
# Importantly, it expects that all sites have either of the four following codes:
# missing data: 			./.
# homozygous reference:		0/0
# heterozygous sites: 		0/1
# homozygous alternative:	1/1
# Set the flag biallelic to FALSE (default), if the vcf file also contains multi-allelic sites (e.g. genotype codes such as 0/2 and 1/2). 
# If your genotypes are encoded differently, you either need to adjust the script, or adjust the input vcf file.

# The script slides through the genome using non-overlapping windows of a fixed number of sites and counts for each window and for each sample:
# - the total number of sites for which genotype information is available (grep -v './.')
# - the number of heterozygous sites (grep '0/1')
# - the number of homozygous alternative sites (grep '1/1')
# The windowsize (default is 20000bp) can be adjusted below with the flag 'winsize'.

# The script goes through 5 preparatory steps:
# 1. if 'do_bgzip' is TRUE:				bgzipping of input vcf file, creating bgz file. This step also includes the removal of lines with information about indels.	
# 2. if 'do_tabix' is TRUE:				index bgzipped vcf file with tabix     
# 3. if 'extract_contiginfo' is TRUE:	create file called 'mylongcontigs.txt' which contains names and length of contig/scaffold names (longer than 5Mb, or other value specified by 'mincontigbp' flag)    
# 4. if 'extract_samples' is TRUE:		create file called 'myvcfsamples.txt' which lists all samples in vcf file
# 5. if 'popscores' is TRUE:			create file called 'allpoppairs.txt' which lists all pairwise population comparisons (based on populations defined in second column of POPFILE. It also creates file headers. 
#										the file 'allpoppairs.txt' is tab separated: first column: pop1, second column: pop2).
# Set corresponding flags to FALSE if these files have been generated before during previous execution of this script.
 
# The main output file will be called 'mywindow.20000.allsites_multi.txt' (depending on the window size you selected).  
# It contains the columns:
# contig startbp endbp nmiss_1 nsites_1 nhet_1 nhomo_1 nmiss_2 nsites_2 nhet_2 nhomo_2 etc
# The data in this output file can be visualized in R using the script 'VCF_windowhe_plotinR.txt'
 
# The nhomo_1 column gives the number of alternative homozygous sites per window (for individual 1). 
# That means: not included are the number of reference homozygous sites. This number can be derived using the formula:
# nrefhomo = nsites - nhet - nhomo
# The total number of homozygous sites is therefore:
# totalhomo = nhomo_ref + nhomo_alt = (nsites - nhet - nhomo) + nhomo = nsites - nhet.
 
# A test run on a mammalian whole genome resequencing dataset of ~100 samples and a window size of 100Kb and 20Kb took 5 and 25 days respectively.
# To speed up the process, you could run the script parallel on different subsets of scaffolds (as defined in the 'mylongcontigs.txt' file.
# If so, make sure to run each command in a different subdirectory, to provide the full path to the vcf file, and to set to flag 'extract_contiginfo' to FALSE when starting the actual run.
 
# The final output file can be analyzed even before the entire process has been completed. 
# For example, run the command:
# cp mywindow.100000.allsites_multi.txt  mywindow.100000.allsites_multi.subset.txt
# For a first examination of the results, run the VCF_windowhe_plotinR.txt in R using as input file the 'mywindow.100000.allsites_multi.subset.txt' file.

## ROH/HE ANALYSES QUICK START GUIDE:
# short step by step guide for ROH-analyses:
# 1. specify the path to TABIX 
# 2. specify the name of the vcf file to the 'MYVCF' flag
# 3. specify the window size (in bp) to the 'winsize' flag.
#	 Consider that He is around 0.002, so that even without missing data a window of 10Kb will on average contain around 20 heterozygous sites.
#	 Low number of heterozygous sites is subject to stochasticity. Therefore, you don't want to go much below on expected value of 10-20 heterozygous sites (after correction for missing data).
# 4. specify the minimum length of contig/scaffold to be considered in the analyses to the 'mincontigbp' flag
# 5. set the flags of the four preparatory steps to TRUE (leave all other flags set to FALSE) and execute the script on the Unix command line.
# 6. wait until the run finishes.
# 7. next, set all four preparatory steps to FALSE, and set the flag 'run_loop' and 'sample_scores' to TRUE. Leave all other flags set to FALSE.
# 8. Execute the script on the Unix command line. This might take hours to days, depending on number of samples.
# 9. Afterwards, transfer the file 'mywindow.20000.allsites_multi.txt' to a directory on your personal computer.
# 10. To analyse and plot the data in R, follow the instructions in the file 'VCF_darwindow.plotinR.txt'.



###########################
TABIX=/opt/software/htslib/htslib-1.9/bin               		# without forward slash at the end (not: note to tabix executable itself, but to bin directory which contains tabix and bgzip executable)
VCFTOOLS=/opt/software/vcftools/vcftools_0.1.17/bin/vcftools	# Needed for LD calculations only
ADMIXTEST=/home/mdejong/bearproject/snpfiles_december2020/slidingwindow121/testrun/VCF_3poptest_admixtools.sh	# Not needed, unless admixture q3 analysis. Note: first read instructions in VCF_3poptest_admixtools.sh script.  

MYVCF=allsites.vcf                                      		# Note: without gz extension, even if input file is gunzipped
POPFILE=mymainpopfile.txt										# Only needed if flag 'pop_scores' is set to TRUE

winsize=20000
mincontigbp=5000000												# minimum length of contig (in bp) to be considered in analysis
suffix="allsites_roh"
biallelic=FALSE
annotated=FALSE
haploiddata=FALSE						# Set to TRUE in case of haploid data. Only useful to count alternative sites (because no heterozygous sites present anyway).

# preparatory steps:
do_bgzip=FALSE
do_tabix=FALSE
extract_contiginfo=FALSE
extract_samples=FALSE

# actual analyses:
run_loop=FALSE							# only set to TRUE after having run the four preparatory steps
sample_scores=TRUE						# sliding window heterozygosity (needed for ROH-analyses)
pop_scores=FALSE
poppair_scores=FALSE
tstv_scores=FALSE
ld_scores=FALSE						
admix_scores=FALSE
###########################







###### PREPARE FILES ######

if [[ -f "${MYVCF}" ]]
	then
	echo "Input: unzipped file."
	grep -B1000000 -m 1 '#CHROM' ${MYVCF} > myvcf.header.txt
	else
	echo "Input: gzipped file."
	zgrep -B1000000 -m 1 '#CHROM' ${MYVCF}.gz > myvcf.header.txt
fi

# index:
if [[ "$do_bgzip" = TRUE ]]
	then
	echo "Zipping with bgzip..."
	echo "This may take up to an hour, depending on the size of the vcf file."
	if [[ -f "${MYVCF}.gz" ]]
	    then
	    echo "Input: gzipped file."
	    gunzip -c ${MYVCF}.gz | grep -v 'INDEL' | $TABIX/bgzip -f > ${MYVCF}.bgz &
	    else
	    if [[ -f "${MYVCF}" ]]
			then
			echo "Input: unzipped file."
			grep -v 'INDEL' $MYVCF | $TABIX/bgzip -f > ${MYVCF}.bgz &
			else
			echo "ERROR: input (gzipped) vcf-file not found. Note that you should not provide the gz extension, even if file is gzipped."
		fi
	fi
	else
	echo "Skipping bgzip step because 'do_bgzip' is set to FALSE."
fi
wait

if [[ "$do_tabix" = TRUE ]]
	then
	echo "Indexing with tabix..."
	echo "This may take several minutes (>up to half an hour), depending on the size of the vcf file."
	$TABIX/tabix -f -p vcf ${MYVCF}.bgz
	else
	echo "Skipping indexing step because 'do_tabix' is set to FALSE."
fi
wait

if [[ "$extract_contiginfo" = TRUE ]]
	then
	echo "Selecting contigs with minimum length (specified by mincontigbp flag)..."
	# extract contig length information:
	grep 'contig' myvcf.header.txt | cut -f1 -d ',' | sed 's/ID=/!/g' | cut -f2 -d '!' > mycontigs.txt
	grep 'contig' myvcf.header.txt | cut -f2 -d ',' | cut -f2 -d '=' | sed 's/>//g' > mylengths.txt
	paste mycontigs.txt mylengths.txt > mycontiglengths.txt
	rm mycontigs.txt mylengths.txt
	# select contigs based on minimum length:
	#awk '$2>5000000' mycontiglengths.txt > mylongcontigs.txt
	awk -v minlength="$mincontigbp" '$2>=minlength' mycontiglengths.txt > mylongcontigs.txt
	ncontigs=$(wc -l mylongcontigs.txt | cut -f1 -d ' ')
    echo "Finished selecting contigs."
    echo "Number of contigs retained: "$ncontigs
	echo "Results stored in the files mycontiglengths.txt and mylongcontigs.txt."
	else
	echo "Not extracting contig length information because the flag 'extract_contiginfo' is set to FALSE."
	echo "Assuming the files 'mycontiglengths.txt' and 'mylongcontigs.txt' are present in the working directory." 
fi
wait

if [[ "$extract_samples" = TRUE ]]
	then
	echo "Retrieving sample info..."
	# bcftools query -l ${MYVCF}.gz > myvcfsamples.txt
	zgrep -m 1 '#CHROM' ${MYVCF}.gz | cut -f10- | tr '\t' '\n' > myvcfsamples.txt
	nrsamples=$(wc -l myvcfsamples.txt | cut -f1 -d ' ')
	seq 1 $nrsamples > mysamplenrs.txt
	
	# create file header:
	if [[ "$annotated" = TRUE ]]
	   then
	   echo "contig startbp endbp totalbp ncoding low_mono low_poly high_mono high_poly" | sed 's/ /\t/g' > header1.tmp.txt
	   else
	   echo "contig startbp endbp totalbp" | sed 's/ /\t/g' > header1.tmp.txt
	fi
	sed 's/^/nmiss_/' mysamplenrs.txt > mysamplenrs.nmiss.tmp.txt
	sed 's/^/nsites_/' mysamplenrs.txt > mysamplenrs.nsites.tmp.txt
	sed 's/^/nhet_/' mysamplenrs.txt > mysamplenrs.nhet.tmp.txt
	sed 's/^/nhomo_/' mysamplenrs.txt > mysamplenrs.nalthomo.tmp.txt
	paste -d '\n' mysamplenrs.nmiss.tmp.txt mysamplenrs.nsites.tmp.txt mysamplenrs.nhet.tmp.txt mysamplenrs.nalthomo.tmp.txt | tr '\n' '\t' > header2.tmp.txt
	if [[ "$sample_scores" = TRUE ]]
	   then
	   paste header1.tmp.txt header2.tmp.txt > mywindowheader.txt
	   else
	   cp header1.tmp.txt mywindowheader.txt
	fi
	rm mysamplenrs.txt mysamplenrs.nsites.tmp.txt mysamplenrs.nmiss.tmp.txt mysamplenrs.nhet.tmp.txt mysamplenrs.nalthomo.tmp.txt header2.tmp.txt header1.tmp.txt 
	echo "Sample info retrieved."
fi





###### RUN LOOP ######

if [[ "$pop_scores" = TRUE ]]
	then
	cut -f2 $POPFILE | sort | uniq > mypopnames.txt
	nrpops=$(wc -l mypopnames.txt | cut -f1 -d ' ')
	seq 1 $nrpops > mypopnrs.txt
	
	# list of all pairwise combinations:
	for ((i=1; i<=nrpops; i++))
		do
		for ((j=1; j<=nrpops; j++))
			do
			if (( $i < $j ))
				then
				echo -e $i'\t'$j
				fi
			done
		done > allpoppairs.txt
	npairwise=$(wc -l allpoppairs.txt | cut -f1 -d ' ')
	sed 's/\t/_/g' allpoppairs.txt > mypoppairnrs.txt
	echo -e "Number of pairwise population comparisons: "$npairwise 
	
	# prepare file headers:
	echo "contig startbp endbp totalbp npoly" | sed 's/ /\t/g' > header1.tmp.txt
	sed 's/^/pi_/' mypopnrs.txt | tr '\n' '\t' > mypopnrs.pi.tmp.txt
	sed 's/^/npoly_/' mypopnrs.txt > mypopnrs.poly.tmp.txt
	sed 's/^/nmono_/' mypopnrs.txt > mypopnrs.mono.tmp.txt
	sed 's/^/nmiss_/' mypopnrs.txt > mypopnrs.miss.tmp.txt
	sed 's/^/dxy_/' mypoppairnrs.txt | tr '\n' '\t' > mypoppairnrs.dxy.tmp.txt
	sed 's/^/meanpopts_/' mypoppairnrs.txt > mymeanpopnrs.ts.tmp.txt
	sed 's/^/meanpoptv_/' mypoppairnrs.txt > mymeanpopnrs.tv.tmp.txt
	sed 's/^/pairts_/' mypoppairnrs.txt > mypoppairnrs.ts.tmp.txt
	sed 's/^/pairtv_/' mypoppairnrs.txt > mypoppairnrs.tv.tmp.txt
	# pi header:
	if [[ "$poppair_scores" = TRUE ]]
		then
		paste header1.tmp.txt mypopnrs.pi.tmp.txt mypoppairnrs.dxy.tmp.txt | tr -s '\t' > mywindowpiheader.txt
		else
		paste header1.tmp.txt mypopnrs.pi.tmp.txt | tr -s '\t' > mywindowpiheader.txt
	fi	
	# npoly header:
	paste -d '\n' mypopnrs.poly.tmp.txt mypopnrs.mono.tmp.txt mypopnrs.miss.tmp.txt | tr '\n' '\t' > mypopnrs.polymono.tmp.txt
	paste header1.tmp.txt mypopnrs.polymono.tmp.txt | tr -s '\t' > mywindowpolyheader.txt
	# tstv header:
	if [[ "$poppair_scores" = TRUE ]]
		then
		paste -d '\n' mymeanpopnrs.ts.tmp.txt mymeanpopnrs.tv.tmp.txt mypoppairnrs.ts.tmp.txt mypoppairnrs.tv.tmp.txt | tr '\n' '\t' > mypopnrs.tstv.tmp.txt
		else
		paste -d '\n' mymeanpopnrs.ts.tmp.txt mymeanpopnrs.tv.tmp.txt | tr '\n' '\t' > mypopnrs.tstv.tmp.txt
	fi
	echo "nts ntv" | sed 's/ /\t/g' > header2.tmp.txt
	paste header1.tmp.txt header2.tmp.txt mypopnrs.tstv.tmp.txt | tr -s '\t' > mywindowtstvheader.txt
	#
	# LD scores
	if [[ "$ld_scores" = TRUE ]]
		then
		echo "contig startbp endbp totalbp nrsnps nrpairs_all dist_all LD_all" | sed 's/ /\t/g' > ldheader.tmp.txt
		sed 's/^/nrpairs_/' mypopnrs.txt > mypopnrs.nrpairs.tmp.txt
		sed 's/^/dist_/' mypopnrs.txt > mypopnrs.dist.tmp.txt
		sed 's/^/LD_/' mypopnrs.txt > mypopnrs.ld.tmp.txt
		paste ldheader.tmp.txt mypopnrs.nrpairs.tmp.txt mypopnrs.dist.tmp.txt mypopnrs.ld.tmp.txt | tr -s '\t' > mywindowldheader.txt 
		rm ldheader.tmp.txt mypopnrs.nrpairs.tmp.txt mypopnrs.dist.tmp.txt mypopnrs.ld.tmp.txt
	fi
	# remove intermediate files:
	rm mypopnrs.txt mypoppairnrs.txt header1.tmp.txt mypopnrs.pi.tmp.txt mypopnrs.poly.tmp.txt mypopnrs.mono.tmp.txt mypopnrs.miss.tmp.txt mypopnrs.polymono.tmp.txt mypoppairnrs.dxy.tmp.txt
	rm mypopnrs.tstv.tmp.txt mypoppairnrs.ts.tmp.txt mypoppairnrs.tv.tmp.txt header2.tmp.txt mymeanpopnrs.ts.tmp.txt mymeanpopnrs.tv.tmp.txt
	else
	if [[ "$ld_scores" = TRUE ]]
		then
		echo "contig startbp endbp totalbp nrsnps nrpairs_all dist_all LD_all" | sed 's/ /\t/g' > mywindowldheader.txt 
	fi
fi


# test run:
# echo 4'\n'41 > mylongcontigs.txt
# or:
# head -2 mylongcontigs.txt > temp.txt && mv temp.txt mylongcontigs.txt


if [[ "$run_loop" = TRUE ]]
	then
	echo "Starting loop..."
	
	# create files in which to store results:
	if [ -f "mywindowhe.${winsize}.${suffix}.txt" ]; then rm mywindowhe.${winsize}.${suffix}.txt; fi
	if [ -f "mywindowheader.txt" ]; then cp mywindowheader.txt mywindowhe.${winsize}.${suffix}.txt; else touch mywindowhe.${winsize}.${suffix}.txt; fi
	if [ -f "mywindowpi.${winsize}.${suffix}.txt" ]; then rm mywindowpi.${winsize}.${suffix}.txt; fi
	if [ -f "mywindowpiheader.txt" ]; then cp mywindowpiheader.txt mywindowpi.${winsize}.${suffix}.txt; else touch mywindowpi.${winsize}.${suffix}.txt; fi
	if [ -f "mywindowpoly.${winsize}.${suffix}.txt" ]; then rm mywindowpoly.${winsize}.${suffix}.txt; fi
	if [ -f "mywindowpolyheader.txt" ]; then cp mywindowpolyheader.txt mywindowpoly.${winsize}.${suffix}.txt; else touch mywindowpoly.${winsize}.${suffix}.txt; fi
	if [[ "$tstv_scores" = TRUE ]]
		then
		if [ -f "mywindowtstv.${winsize}.${suffix}.txt" ]; then rm mywindowtstv.${winsize}.${suffix}.txt; fi
		if [ -f "mywindowtstvheader.txt" ]; then cp mywindowtstvheader.txt mywindowtstv.${winsize}.${suffix}.txt; else touch mywindowtstv.${winsize}.${suffix}.txt; fi
	fi
	if [[ "$ld_scores" = TRUE ]]
		then
		if [ -f "mywindowld.${winsize}.${suffix}.txt" ]; then rm mywindowld.${winsize}.${suffix}.txt; fi
		if [ -f "mywindowldheader.txt" ]; then cp mywindowldheader.txt mywindowld.${winsize}.${suffix}.txt; else touch mywindowld.${winsize}.${suffix}.txt; fi
		else
		echo "Not calculating linkage disequilibrium scores."
	fi
	
	if [[ "$sample_scores" = TRUE ]]
		then
		nrsamples=$(wc -l myvcfsamples.txt | cut -f1 -d ' ')
		echo "Number of samples:" $nrsamples
		else
		echo "Not calculating sample specific scores."
	fi
	
	if [[ "$admix_scores" = TRUE ]]
		then
		if [ -f "mywindowadmix.${winsize}.${suffix}.txt" ]; then rm mywindowadmix.${winsize}.${suffix}.txt; fi
		touch mywindowadmix.${winsize}.${suffix}.txt
	fi
	
	if [[ "$pop_scores" = TRUE ]]
		then
		nrpops=$(wc -l mypopnames.txt | cut -f1 -d ' ')
		echo "Number of populations:" $nrpops
		if [[ "$poppair_scores" = TRUE ]]
			then
			nrpoppairs=$(wc -l mypopnames.txt | cut -f1 -d ' ')
			echo "Number of population pairs:" $nrpoppairs
			else
			echo "Not calculating population pair scores."
		fi
		else
		echo "Not calculating population scores."
	fi
	
	# How many contigs?
	nrcontigs=$(wc -l mylongcontigs.txt | cut -f1 -d ' ')
	echo "Total number of selected contigs/scaffolds (as specified in the 'mylongcontigs.txt' file):" $nrcontigs
	
	for contignr in $(seq 1 $nrcontigs)
		do
		contigname=$(awk -v myline="$contignr" 'NR==myline' mylongcontigs.txt | cut -f1)
		contiglength=$(awk -v myline="$contignr" 'NR==myline' mylongcontigs.txt | cut -f2)
		echo -e $contignr'\t'$contigname'\t'$contiglength
		contiglength2=$(( $contiglength + $winsize ))
		for endbp in $(seq $winsize $winsize $contiglength2)
			do
			startbp=$(( $endbp - $winsize + 1 ))
			if (( $endbp > $contiglength ))
				then
				endbp=$contiglength
				winsize2=$(( $endbp - $startbp + 1 ))
				else
				winsize2=$winsize
			fi
			# CALCULATE WINDOW STATS:
			$TABIX/tabix ${MYVCF}.bgz ${contigname}:${startbp}-${endbp} > myvcfregion.${winsize}.allcolumns.noindels.txt
			cut -f10- myvcfregion.${winsize}.allcolumns.noindels.txt > myvcfregion.${winsize}.noindels.txt
			cut -f1-9 myvcfregion.${winsize}.allcolumns.noindels.txt > myvcfregion.${winsize}.metainfo.noindels.txt
			totalbp=$(wc -l myvcfregion.${winsize}.metainfo.noindels.txt | cut -f1 -d ' ')
			#
			if [[ "$annotated" = TRUE ]]
				then 
				awk '$5!="A,C,G,T"' myvcfregion.${winsize}.allcolumns.noindels.txt | cut -f 4,5 > myvcfregion.${winsize}.onlypoly.alleles.txt
				awk '$5!="A,C,G,T"' myvcfregion.${winsize}.allcolumns.noindels.txt | cut -f 10- > myvcfregion.${winsize}.onlypoly.txt
				grep -v 'intergenic' -a --no-group-separator myvcfregion.${winsize}.metainfo.noindels.txt > myvcfregion.${winsize}.metainfo.coding.txt
				ncoding=$(wc -l myvcfregion.${winsize}.metainfo.coding.txt | cut -f1 -d ' ')
				awk '$5=="A,C,G,T"' myvcfregion.${winsize}.metainfo.coding.txt > myvcfregion.${winsize}.mono.txt
				awk '$5!="A,C,G,T"' myvcfregion.${winsize}.metainfo.coding.txt > myvcfregion.${winsize}.poly.txt
				low_mono=$(grep 'LOW' myvcfregion.${winsize}.mono.txt | grep -v 'HIGH' | grep -v 'MODERATE' | wc -l | cut -f1 -d ' ')
				low_poly=$(grep 'LOW' myvcfregion.${winsize}.poly.txt | grep -v 'HIGH' | grep -v 'MODERATE' | wc -l | cut -f1 -d ' ')
				high_mono=$(grep 'HIGH' myvcfregion.${winsize}.mono.txt | grep -v 'LOW' | grep -v 'MODERATE' | wc -l | cut -f1 -d ' ')
				high_poly=$(grep 'HIGH' myvcfregion.${winsize}.poly.txt | grep -v 'LOW' | grep -v 'MODERATE' | wc -l | cut -f1 -d ' ')			
				echo -e $contigname'\t'$startbp'\t'$endbp'\t'$totalbp'\t'$ncoding'\t'$low_mono'\t'$low_poly'\t'$high_mono'\t'$high_poly > mywindowhe.${winsize}.tmp.txt
				else
				awk '$5!="."' myvcfregion.${winsize}.allcolumns.noindels.txt | cut -f 4,5 > myvcfregion.${winsize}.onlypoly.alleles.txt
				awk '$5!="."' myvcfregion.${winsize}.allcolumns.noindels.txt | cut -f 10- > myvcfregion.${winsize}.onlypoly.txt
				echo -e $contigname'\t'$startbp'\t'$endbp'\t'$totalbp > mywindowhe.${winsize}.tmp.txt
			fi
			# CALCULATE LD:
			if [[ "$ld_scores" = TRUE ]]
				then 
				cat myvcf.header.txt myvcfregion.${winsize}.allcolumns.noindels.txt > myvcfregion.withheader.vcf
				$VCFTOOLS --vcf myvcfregion.withheader.vcf --geno-r2 --mac 12 --ld-window-bp 1000 --out myldscores
				awk -v FS='\t' '$5!="-nan"' myldscores.geno.ld > myldscores.nonan.txt
				nrsnps=$(wc -l myvcfregion.${winsize}.onlypoly.alleles.txt | cut -f1 -d ' ')
				nrpairs=$(wc -l myldscores.nonan.txt | cut -f1 -d ' ')
				ldmean=$(awk '{ sum += $5; n++ } END { if (n > 0) print sum / n; }' myldscores.nonan.txt )
				distmean=$(awk -v FS='\t' '$6=$3-$2' myldscores.nonan.txt | awk '{ sum += $6; n++ } END { if (n > 0) print sum / n; }')
				echo -e $contigname'\t'$startbp'\t'$endbp'\t'$totalbp'\t'$nrsnps'\t'$nrpairs'\t'$distmean'\t'$ldmean > mywindowld.${winsize}.tmp.txt
				fi
			#
			# CALCULATE 3pop-test score:
			if [[ "$admix_scores" = TRUE ]]
				then
				cat myvcf.header.txt myvcfregion.${winsize}.allcolumns.noindels.txt > myvcfregion.withheader.vcf
				${ADMIXTEST} myvcfregion.withheader.vcf
				sed -i "s/$/\t${contigname}\t${startbp}\t${endbp}/" admixtools.outtable.txt
				cat admixtools.outtable.txt >> mywindowadmix.${winsize}.${suffix}.txt
			fi
			# CALCULATE INDIVIDUAL STATS:
			if [[ "$sample_scores" = TRUE ]]
				then
				for indnr in $(seq 1 $nrsamples)
					do  
					# count number of (missing) data points per individual:
					cut -f$indnr myvcfregion.${winsize}.noindels.txt | grep -v '\./\.' > myvcfcolumn.${winsize}.txt 
					totalsites=$(wc -l myvcfcolumn.${winsize}.txt | cut -f1 -d ' ')
					missingsites=$(( $winsize2 - $totalsites ))
					# count number of heterozygous and alternative homozygous sites per individual:
					if [[ "$biallelic" = TRUE ]]
						then
						heterosites=$(grep '0/1' -a --no-group-separator myvcfcolumn.${winsize}.txt | wc -l | cut -f1 -d ' ')
						althomosites=$(grep '1/1' -a --no-group-separator myvcfcolumn.${winsize}.txt | wc -l | cut -f1 -d ' ')
						else
						if [[ "$haploiddata" = TRUE ]]
							then
							heterosites=0
							althomosites=$(cut -f1 -d ':' myvcfcolumn.${winsize}.txt | grep -v '0' -a --no-group-separator | wc -l | cut -f1 -d ' ')
							else
							heterosites=$(grep '0/1\|0/2\|0/3\|1/2\|1/3\|2/3' -a --no-group-separator myvcfcolumn.${winsize}.txt | wc -l | cut -f1 -d ' ')
							althomosites=$(grep '1/1\|2/2\|3/3' -a --no-group-separator myvcfcolumn.${winsize}.txt | wc -l | cut -f1 -d ' ')
							fi
						heterosites=$(grep '0/1\|0/2\|0/3\|1/2\|1/3\|2/3' -a --no-group-separator myvcfcolumn.${winsize}.txt | wc -l | cut -f1 -d ' ')
						althomosites=$(grep '1/1\|2/2\|3/3' -a --no-group-separator myvcfcolumn.${winsize}.txt | wc -l | cut -f1 -d ' ')
					fi
					# add scores to temporary windowhe file:
					if [[ "$annotated" = TRUE ]]
						then	
						sed -i "s/$/\t${missingsites}\t${totalsites}\t${ncoding}\t${heterosites}\t${althomosites}/" mywindowhe.${winsize}.tmp.txt
						else
						sed -i "s/$/\t${missingsites}\t${totalsites}\t${heterosites}\t${althomosites}/" mywindowhe.${winsize}.tmp.txt
					fi
					done
			fi
			# CALCULATE POPULATION STATS:
			if [[ "$pop_scores" = TRUE ]]
				then
				cut -f1-4 mywindowhe.${winsize}.tmp.txt > mywindowpi.${winsize}.tmp.txt
				cut -f1-4 mywindowhe.${winsize}.tmp.txt > mywindowpoly.${winsize}.tmp.txt
				if [[ "$tstv_scores" = TRUE ]]
					then
					cut -f1-4 mywindowhe.${winsize}.tmp.txt > mywindowtstv.${winsize}.tmp.txt
				fi
				for popnr in $(seq 1 $nrpops)
					do
					# select samples per population:
					mypopname=$(awk -v awkvar="$popnr" 'NR==awkvar' mypopnames.txt)
					awk -v awkvar="$mypopname" '$2==awkvar' $POPFILE | cut -f1 > mypopsamples.txt 
					popcolumns=$(grep -n -f 'mypopsamples.txt' myvcfsamples.txt | cut -f1 -d ':' | tr '\n' ',' | sed 's/.$//')
					npoly=$(wc -l myvcfregion.${winsize}.onlypoly.txt | cut -f1 -d ' ')
					if [[ "$npoly" == 0 ]]
						then
						echo "WARNING: 0 polymorphic sites."
						if [[ "$popnr" == 1 ]]
                            then
                            sed -i "s/$/\t${npoly}\tNA/" mywindowpi.${winsize}.tmp.txt
							echo "NA NA NA NA" > myallelefreqs.txt
							else
                            sed -i "s/$/\tNA/" mywindowpi.${winsize}.tmp.txt
							echo "NA NA NA NA" > myallelefreqs.tmp2.txt
							mv myallelefreqs.tmp2.txt myallelefreqs.txt
                        fi
						else
						cut -f$popcolumns myvcfregion.${winsize}.onlypoly.txt > myvcfregion.pop.vcf
						# allele count:
						perl -lne 'print s/0\/0//g' myvcfregion.pop.vcf | sed 's/^$/0/g' > n00.txt
						perl -lne 'print s/0\/1//g' myvcfregion.pop.vcf | sed 's/^$/0/g' > n01.txt
						perl -lne 'print s/0\/2//g' myvcfregion.pop.vcf | sed 's/^$/0/g' > n02.txt
						perl -lne 'print s/0\/3//g' myvcfregion.pop.vcf | sed 's/^$/0/g' > n03.txt
						perl -lne 'print s/1\/1//g' myvcfregion.pop.vcf | sed 's/^$/0/g' > n11.txt
						perl -lne 'print s/1\/2//g' myvcfregion.pop.vcf | sed 's/^$/0/g' > n12.txt
						perl -lne 'print s/1\/3//g' myvcfregion.pop.vcf | sed 's/^$/0/g' > n13.txt
						perl -lne 'print s/2\/2//g' myvcfregion.pop.vcf | sed 's/^$/0/g' > n22.txt
						perl -lne 'print s/2\/3//g' myvcfregion.pop.vcf | sed 's/^$/0/g' > n23.txt
						perl -lne 'print s/3\/3//g' myvcfregion.pop.vcf | sed 's/^$/0/g' > n33.txt
						perl -lne 'print s/\.\/\.//g' myvcfregion.pop.vcf | sed 's/^$/0/g' > nmiss.txt
						paste n00.txt n01.txt n02.txt n03.txt n11.txt n12.txt n13.txt n22.txt n23.txt n33.txt nmiss.txt > popgenotypes.txt
						# allele counts:
						awk -v OFS='\t' '{ print $1 + $1 + $2 + $3 + $4, $5 + $5 + $2 + $6 + $7, $8 + $8 + $3 + $6 + $9, $10 + $10 + $4 + $7 + $10, $11 + $11 ;  }' popgenotypes.txt > myallelecounts.txt
						awk -v OFS='\t' '{ print $1, $2, $3, $4, $5, $1 + $2 + $3 + $4 ; }' myallelecounts.txt > myallelecounts2.txt
						# allele frequencies:
						awk -v OFS='\t' '{ if($6 != 0) { $7 = $1 / $6; $8 = $2 / $6; $9 = $3 / $6; $10 = $4 / $6  } else {$7 = 0; $8 = 0; $9 = 0; $10 = 0} }1' myallelecounts2.txt | cut -f7- > myallelefreqs.tmp.txt
						# sequence similarity:
						awk -v OFS='\t' '{ $5 = $1 * $1 + $2 * $2 + $3 * $3 + $4 * $4 }1' myallelefreqs.tmp.txt | cut -f5 > myseqsimilarity.tmp.txt
						poppi=$(awk '{ total += $1 } END {print total/NR}' myseqsimilarity.tmp.txt)
						if [[ "$popnr" == 1 ]]
							then
							sed -i "s/$/\t${npoly}\t${poppi}/" mywindowpi.${winsize}.tmp.txt
							mv myallelefreqs.tmp.txt myallelefreqs.txt
							mv myseqsimilarity.tmp.txt myseqsimilarity.txt
							else
							sed -i "s/$/\t${poppi}/" mywindowpi.${winsize}.tmp.txt
							paste myallelefreqs.txt myallelefreqs.tmp.txt > myallelefreqs.tmp2.txt
							mv myallelefreqs.tmp2.txt myallelefreqs.txt
							paste myseqsimilarity.txt myseqsimilarity.tmp.txt > myseqsimilarity.tmp2.txt
							mv myseqsimilarity.tmp2.txt myseqsimilarity.txt
						fi
						# number of polymorphic sites:
						npoppoly=$(grep -a -w -v '1' myallelefreqs.txt | wc -l | cut -f1 -d ' ')
						npopmono=$(grep -a -w '1' myallelefreqs.txt | grep -v 'NA' | wc -l | cut -f1 -d ' ')
						npopna=$(grep -a 'NA' myallelefreqs.txt | wc -l | cut -f1 -d ' ')
						if [[ "$popnr" == 1 ]]
							then
							sed -i "s/$/\t${npoly}\t${npoppoly}\t${npopmono}\t${npopna}/" mywindowpoly.${winsize}.tmp.txt
							else
							sed -i "s/$/\t${npoppoly}\t${npopmono}\t${npopna}/" mywindowpoly.${winsize}.tmp.txt
						fi
					fi
					done
				# CALCULATE PAIRWISE POPULATION STATS (Dxy):
				if [[ "$poppair_scores" = TRUE ]]
					then
					for pairnr in $(seq 1 $npairwise)
						do
						pop1=$(awk -v awkvar="$pairnr" 'NR==awkvar' allpoppairs.txt | cut -f1)
						pop2=$(awk -v awkvar="$pairnr" 'NR==awkvar' allpoppairs.txt | cut -f2)
						firstcol1=$(( $pop1 * 4 - 4 + 1 ))
						lastcol1=$(( $pop1 * 4 ))
						firstcol2=$(( $pop2 * 4 - 4 + 1 ))
						lastcol2=$(( $pop2 * 4 ))
						pop1cols=$(seq $firstcol1 $lastcol1 | tr '\n' ',' | sed 's/.$//')
						pop2cols=$(seq $firstcol2 $lastcol2 | tr '\n' ',' | sed 's/.$//')
						cut -f$pop1cols myallelefreqs.txt > popfreqs1.txt
						cut -f$pop2cols myallelefreqs.txt > popfreqs2.txt
						paste popfreqs1.txt popfreqs2.txt > pairfreqs.txt
						# sequence similarity:
						awk -v OFS='\t' '{ $9 = $1 * $5 + $2 * $6 + $3 * $7 + $4 * $8 }1' pairfreqs.txt | cut -f9 > mydxy.txt
						poppairdxy=$(awk '{ total += $1 } END {print total/NR}' mydxy.txt)
						sed -i "s/$/\t${poppairdxy}/" mywindowpi.${winsize}.tmp.txt
						# transition similarity biallelic alleles:
						if [[ "$tstv_scores" = TRUE ]]
							then
							paste myvcfregion.${winsize}.onlypoly.alleles.txt pairfreqs.txt | grep -a -v ',' > pairfreqs.bialleles.txt
							awk '$1 == "A" && $2 == "G" || $1 == "G" && $2 == "A" || $1 == "C" && $2 == "T" || $1 == "T" && $2 == "C"' pairfreqs.bialleles.txt | cut -f3- > pairfreqs.ts.txt
							awk '$1 == "A" && $2 == "C" || $1 == "C" && $2 == "A" || $1 == "A" && $2 == "T" || $1 == "T" && $2 == "A" || $1 == "G" && $2 == "C" || $1 == "C" && $2 == "G" || $1 == "G" && $2 == "T" || $1 == "T" && $2 == "G"' pairfreqs.bialleles.txt | cut -f3- > pairfreqs.tv.txt
							awk -v OFS='\t' '{ $9 = $1 * $2 + $5 * $6 }1' pairfreqs.ts.txt | cut -f9 > mymeanpopts.txt
							awk -v OFS='\t' '{ $9 = $1 * $2 + $5 * $6 }1' pairfreqs.tv.txt | cut -f9 > mymeanpoptv.txt
							awk -v OFS='\t' '{ $9 = $1 * $6 + $6 * $1 }1' pairfreqs.ts.txt | cut -f9 > mypairts.txt
							awk -v OFS='\t' '{ $9 = $1 * $6 + $6 * $1 }1' pairfreqs.tv.txt | cut -f9 > mypairtv.txt
							meanpopts=$(awk '{ total += $1 } END {print total/NR}' mymeanpopts.txt)
							meanpoptv=$(awk '{ total += $1 } END {print total/NR}' mymeanpoptv.txt)
							poppairts=$(awk '{ total += $1 } END {print total/NR}' mypairts.txt)
							poppairtv=$(awk '{ total += $1 } END {print total/NR}' mypairtv.txt)
							if [[ "$pairnr" == 1 ]]
								then
								nts=$(wc -l pairfreqs.ts.txt | cut -f1 -d ' ')
								ntv=$(wc -l pairfreqs.tv.txt | cut -f1 -d ' ')
								sed -i "s/$/\t${npoly}\t${nts}\t${ntv}\t${meanpopts}\t${meanpoptv}\t${poppairts}\t${poppairtv}/" mywindowtstv.${winsize}.tmp.txt
								else
								sed -i "s/$/\t${meanpopts}\t${meanpoptv}\t${poppairts}\t${poppairtv}/" mywindowtstv.${winsize}.tmp.txt
							fi
						fi
						done
				fi
			fi
			# ADD STATS TO EXISTING FILE (containing stats for previous windows):
			cat mywindowhe.${winsize}.tmp.txt >> mywindowhe.${winsize}.${suffix}.txt
			if [[ "$pop_scores" = TRUE ]]
				then
				cat mywindowpoly.${winsize}.tmp.txt >> mywindowpoly.${winsize}.${suffix}.txt
				cat mywindowpi.${winsize}.tmp.txt >> mywindowpi.${winsize}.${suffix}.txt
				if [[ "$tstv_scores" = TRUE ]]
					then
					cat mywindowtstv.${winsize}.tmp.txt >> mywindowtstv.${winsize}.${suffix}.txt
				fi
			fi
			if [[ "$ld_scores" = TRUE ]]
				then
				cat mywindowld.${winsize}.tmp.txt >> mywindowld.${winsize}.${suffix}.txt
			fi
			done
		done
	
	# REMOVE INTERMEDIATE FILES:
	rm myvcf.header.txt myvcfregion*noindels.txt mywindowhe*tmp.txt
	
	if [[ "$sample_scores" = TRUE ]]
		then
		rm myvcfcolumn*txt
	fi
	
	if [[ "$ld_scores" = TRUE ]]
		then
		rm myldscores.geno.ld myldscores.nonan.txt myldscores.log myvcfregion.withheader.vcf 
	fi
	
	if [[ "$pop_scores" = TRUE ]]
		then
		rm allpoppairs.txt myallelefreqs.tmp.txt myallelefreqs.txt mypopnames.txt mypopsamples.txt mywindowpi*tmp.txt mywindowpiheader.txt 
		rm n00.txt n01.txt n02.txt n03.txt n11.txt n12.txt n13.txt n22.txt n23.txt n33.txt nmiss.txt popgenotypes.txt myallelecounts.txt myallelecounts2.txt myseqsimilarity.tmp.txt myseqsimilarity.txt  	
		rm mywindowpolyheader.txt  mywindowpoly*tmp.txt myvcfregion.pop.vcf myvcfregion*onlypoly.txt myvcfregion*onlypoly.alleles.txt
		if [[ "$poppair_scores" = TRUE ]]
			then
			pairfreqs.txt popfreqs1.txt popfreqs2.txt mydxy.txt pairfreqs.bialleles.txt
		fi
		if [[ "$tstv_scores" = TRUE ]]
			then
			rm mymeanpopnrs.ts.tmp.txt mymeanpopnrs.tv.tmp.txt mymeanpopts.txt mymeanpoptv.txt mypairts.txt mypairtv.txt mywindowtstv*tmp.txt mywindowtstvheader.txt pairfreqs.ts.txt pairfreqs.tv.txt
		fi
	fi
	
	echo "Analysis finished."
	else
	echo "Flag run_loop is set to FALSE. Not running analyses. Exiting."
fi





################################################

