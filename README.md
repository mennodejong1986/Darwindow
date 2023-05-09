# Darwindow

Darwindow is a small tool, consisting of a Unix and a R script, to calculate and plot population-genetic estimates on a sliding-window basis, using as input a gVCF file  (i.e., a vcf-file containing information on both monomorphic and polymorphic sites for the entire genome). 

Darwindow is particularly useful to perform run of homozygosity (ROH) analyses. The advantage of Darwindow compared to other ROH-detection software is that Darwindow allows the user to evaluate the accuracy of the ROH calls through visual examination of heterozygosity levels in regions marked as ROH (grey rectangles in plots with prefix 'He_withROH_linechart', generated by the runindscaffold function).

The average genome-wide heterozygosity estimates produced by Darwindow are near-identical to the estimates obtained with 'bcftools stats -s -', assuming that indels have been removed from the input vcf-file using the command 'zgrep -v "INDEL" data.vcf.gz | gzip > data.noindels.vcf.gz' (this step is included in Darwindow pipeline).



### Instructions for running 'VCF_darwindow.sh' script on Unix command line

In order to run Darwindow in the Unix command line, follow the instructions in the top section of the VCF_darwindow.sh script.
This will generate file(s) containing window-based counts. 

The main output file will start with the prefix 'mywindowhe' and contains the columns:
'contig startbp endbp totalbp nmiss_1 nsites_1 nhet_1 nhomo_1 nmiss_2 nsites_2 nhet_2 nhomo_2 nmiss_3 nsites_3 nhet_3 nhomo_3 etc'

The columns 'nmiss_1', 'nsites_1', 'nhet_1' and 'nhomo_1' give for each window the number of missing sites, the number of non-missing sites, the number of heterozygous sites and the number of alternative homozygous sites observed for individual 1 (first individual in the vcf-file). The columns 'nmiss_2', 'nsites_2', 'nhet_2' and 'nhomo_2 give these counts for individual 2, and so on. 


### Instructions for subsequently running 'VCF_windowhe_plotinR.txt' script in R

The main output file can be further analysed and plotted in R using the script 'VCF_windowhe_plotinR.txt'.
To do so for the example dataset (135 bears, 3 chromosomes), execute in R the following commands:

**First load all required functions:**

*source("VCF_darwindow.plotinR.txt")*

*if(!"zoo"%in%rownames(installed.packages())){install.packages("zoo")}*

*if(!"graphics"%in%rownames(installed.packages())){install.packages("graphics")}*

*library("zoo")*

*library("graphics")*

**Next define the settings:**

Window size in bp:

*window_size	<- 20000*		  

Minimum number of adjacent windows to be considered as a ROH (for example: if n_windows is set 10, and window size is 20000, then reported ROHs are minimum 200Kb):

*nr_windows	<- 10*			    

Maximum amount of missing data per window:

*miss_max	  <- 0.8*         


**Import data:**

*mywd		<- "C:/path/to/directory/"*

*setwd(mywd)*

*getwindowdata(maxmiss=0.8,suffix="20000.brownbears.three_scaffolds.txt",vcfsamples="myvcfsamples.txt",samplefile="popfile.txt",annotated=FALSE,indlevel=TRUE,poplevel=FALSE,mydir=mywd)*

**Define population order and optionally exclude populations:**

*mypoporder	<- c("MiddleEast","Himalaya","Europe","SouthScand","MidScand","NorthScand","Baltic","Ural","CentreRus2","CentreRus","Yakutia","Amur","Hokkaido","Sakhalin","Magadan","Kamtchatka","Aleutian","Kodiak","Alaska","ABCa","ABCbc","ABCcoast2","Westcoast","ABCcoast1","HudsonBay","polar","Black")* 

*reorder_pop(poporder=mypoporder)*

**Calculate genome-wide heterozygosity:**

*calcwindowhe(maxmiss=miss_max)*

*calcregionhe(maxmiss=miss_max,nwindows=nr_windows)*

**Plot heterozygosity:**

*popboxplot(export="pdf",mywidth=0.5)*

*indhisto(export="pdf",plotname="He_histo_region",inputdf=dwd$regionhedf,missdf=NULL,windowsize=window_size,nwindows=nr_windows,mybreaks=seq(-0.01,5,0.005),xmax=0.55,ymax=15,legendcex=1)*

*indbarplot(export="pdf",mywidth=0.5)*

*indboxplot(export="pdf",inputdf=dwd$hedf,plotname="Genomewide_windowHe",ylabel="Heterozygosity (%)",yline=3.25,samplesize=500,maxmiss=miss_max,ymax=0.95,mywidth=0.5)*

**Detect runs of homozygosity:**

Either specify a universal threshold heterozygosity value for all individuals:

*hethres_vec	<- 0.05*	

Or alternatively specify threshold per individual:

*hethres_vec	<- ifelse(dwd$ind$pop=="polar",0.001,0.05)*

Detect ROHs based on the specified threshold:

*findroh(silent=TRUE,hethreshold=hethres_vec,min_rle_length=1,windowsize=window_size,nwindows=nr_windows)*

*getrohlengths(windowsize=window_size,nrwindows=nr_windows)*

*getrohbin()*

**Plot runs of homozygosity:**

*runindscaffold(height_unit=1,do_export=TRUE,input_df1=dwd$hedf,input_df2=dwd$frohdf,plot_label="He_withROH",add_roh=TRUE,add_he=TRUE,add_dxy=FALSE,max_miss=0.9,n_windows=nr_windows,min_rle_len=1,window_size=window_size,line_width=0.1)*

Visually examine the output line charts. Do regions marked as run of homozygosity (grey areas) indeed have low heterozygosity?
If not, try different settings (i.e.: use different values for he_thres_vec and/or nr_windows).
If yes, then you can proceed and create the plots with ROH summary statistics.

**Plot ROH summary statistics:**

*popboxplot(export="pdf",ymax=NULL,indscore="froh",plotname="Genomewide_froh",ylabel="F_roh",mywidth=0.5)*

*indscatter(export="pdf",plotname="Lroh_vs_Nroh",xscore="nroh",yscore="lroh",xlabel="Number of ROHs",ylabel="Total ROH length (Mb)",legendpos="bottomright",legendcex=1,yline=5.5)*

*indscatter(export="pdf",plotname="Froh_vs_He",xscore="regionhe",yscore="froh",xlabel="Genome wide He",ylabel="F (ROH-content)",legendpos="topright",legendcex=0.85,yline=5.75)*

*indscatter(export="pdf",plotname="Froh_mean_vs_sd",xscore="froh",yscore="froh_sd_scaffold",xlabel="F-roh mean",ylabel="F-roh sd (across chromosomes)",addlegend=FALSE,yline=5.75)*

The most informative ROH summary plot is arguably the stacked barplot:

*rohbarplot(inputdf=dwd$frohbindf,ylabel="F-roh",plotname="ROHf_barplot",export="pdf",yline=3,mywidth=0.2,legendcex=1.75,addlegend=TRUE,mycolours=NULL,ypopcol=0.78,legx=30,legy=0.725)*

*rohbarplot(inputdf=dwd$nrohbindf,ylabel="# ROHs",plotname="ROHn_barplot",export="pdf",yline=4.5,mywidth=0.2,legendcex=1.75,addlegend=TRUE,mycolours=NULL,ypopcol=1850,legx=20,legy=1700)*

If you want to use the plot for scientific posters, you could vary the background colour:

*rohbarplot(inputdf=dwd$frohbindf,ylabel="F-roh",plotname="ROHf_barplot",export="pdf",yline=3,mywidth=0.2,legendcex=1.75,addlegend=TRUE,mycolours=NULL,ypopcol=0.78,legx=30,legy=0.725,mybg="lightblue4",axiscol="grey80")*




