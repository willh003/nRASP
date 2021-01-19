#Ifdef ARrtGlobals
#pragma rtGlobals=1        // Use modern global access method.
#else
#pragma rtGlobals=3        // Use strict wave reference mode
#endif 
#include ":AsylumResearch:Code3D:Initialization"
#include ":AsylumResearch:Code3D:MotorControl"
#include ":AsylumResearch:Code3D:Environ"

// INTERNAL NOTES FOR HUEY AFM LABS:
// HEY WILLIAM, DON'T FORGET to make a new input on the nanorasp panel for the variable: trgt_depth.
// ALSO remove extraneous info from nanorasp panel.
// ALSO update help file of instructions--they seem outdated at this point.
// FINALLY note that I changed digmax to digpfr (don't fret, the UPPERCASE and the lowercase versions kept their cases).



Override Function/S LithoDriveDAC(TipParms)
        Struct ARTipHolderParms &TipParms
        return "$HeightLoop.Setpoint"
End //


Menu "Macros" // Put panel in Macros menu
	"nanoRASP Panel", NanoRASP_Panel()
End


Function CheckIncProc(cba) : CheckBoxControl
	STRUCT WMCheckboxAction &cba
	NVAR increment_check = root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':increment_check
	NVAR img_num = root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':img_num
	switch(cba.eventCode)
	case 2: // Mouse up
	Variable checked = cba.checked
		switch(checked)
			case 1:
			 	increment_check = 1
				break
			case 0: 
				increment_check = 0
				break
		endswitch
	break
	case -1: // Control being killed
		break
	endswitch
	return 0
End


Function CheckKProc(cba) : CheckBoxControl
	STRUCT WMCheckboxAction &cba
	NVAR KVAL = root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':KVAL
	switch(cba.eventCode)
		case 2: // Mouse up
			Variable checked = cba.checked
				if (checked == 0)
					KVAL = 0
				endif
		break
		case -1: // Control being killed
		break
	endswitch
	return 0
End


Function ResetExpButton(ba) : ButtonControl // Handles Reset Experiment queries
	STRUCT WMButtonAction &ba
	switch(ba.eventCode)
		case 2: // Mouse up
			if (CmpStr(ba.ctrlName,"bExp") == 0)
				ResetExp()
			endif
		break
	endswitch
	return 0
End


Function LoadExcelButton(ba) : ButtonControl // Handles Load Excel sheet queries
	STRUCT WMButtonAction &ba
	switch(ba.eventCode)
		case 2: // Mouse up
			if (CmpStr(ba.ctrlName,"bLoad") == 0)
				FlipExcel("","","","A1","IV256")
			endif
		break
	endswitch
	return 0
End


Function InitButton(ba) : ButtonControl // Handles Reset Experiment queries
	STRUCT WMButtonAction &ba
	switch(ba.eventCode)
		case 2: // Mouse up
			if (CmpStr(ba.ctrlName,"bExp") == 0)
				InitCustomScan()
			endif
		break
	endswitch
	return 0
End


// CreatePackageData(), GetPackageDFREF() allow this to be ported to any computer without other setup (so just copy/paste code to dads computer)
// Handles folder creation for global variables
Function/DF CreatePackageData() // Called only from GetPackageDFREF
	// Create the package data folder
	NewDataFolder/O root:packages:MFP3D:XPT:Cypher:GlobalVars
	NewDataFolder/O root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals'
	// Create a data folder reference variable
	DFREF dfr = root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals'
	// Create and initialize globals
	Variable/G dfr:DIGPFR= 10
	Variable/G dfr:VTHRESHOLD = 4
	Variable/G dfr:VMAX = 8
	Variable/G dfr:VSP = 3
	Variable/G dfr:KVAL = .05
	Variable/G dfr:DFCHANNEL = 2
	Variable/G dfr:HTCHANNEL = 0
	Variable/G dfr:img_num = 0
	Variable/G dfr:total_images = 200
	Variable/G dfr:should_we_finish = 0
	Variable/G dfr:increment_check = 0
	Variable/G dfr:trgt_depth = 25
	return dfr
End


Function/DF GetPackageDFREF()
	DFREF dfr = root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals'
	if (DataFolderRefStatus(dfr) != 1) // Data folder does not exist?
		DFREF dfr = CreatePackageData() // Create package data folder
	endif
	return dfr
End


//	THE MAIN ACTION FOR NRASP IS HERE:

//	THE MAIN ACTION FOR NRASP IS HERE:
Function/WAVE getForce()
	SetDataFolder root:Packages:MFP3D:XPT:Cypher
	Wave trgt_scaled
	
	DFREF dfr = root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals'
	NVAR DIGPFR = dfr:DIGPFR			// Size of interval of heights (in nm) where voltage will start converging. Smaller = more gradient in lith_force
	NVAR VTHRESHOLD = dfr:VTHRESHOLD	// Voltage at which it starts actually digging
	NVAR VMAX = dfr:VMAX				// Max voltage allowed
	NVAR VSP = dfr:VSP					// Setpoint voltage (what to apply when diff = 0)
	NVAR KVAL = dfr:KVAL				// Scalar for deflection
	NVAR DFCHANNEL = dfr:DFCHANNEL		// Channel containing defl data
	NVAR HTCHANNEL = dfr:HTCHANNEL		// Channel containing ht data
	
	Make/O/N = (256, 256) lith_current_all, lith_ht, lith_defl, ht_true
	String filename = GetFilename()	
	String indexString = GS("SaveImage")
	NewPath/O folderpath, indexstring  	// folderpath is the symbolic path to the data folder specified in the master pannel
	LoadWave/M/O/B="C=256, N=current1;"/P=folderpath, filename // This should be final call for loading the file
	
	// Copy loaded wave to 'current'
	Duplicate/O/WAVE $filename, $"lith_current_all" // $ is necessary because of how IGOR loops/duplicates stuff
	lith_ht[][] = lith_current_all[x][y][HTCHANNEL]
	lith_defl[][] = lith_current_all[x][y][DFCHANNEL]
	Reverse/DIM=1/P lith_ht 		// We realized the saved height and deflection data are flipped vertically w/r the images (top at the bottom).
	Reverse/DIM=1/P lith_defl
	ht_true = lith_ht  + (KVAL * lith_defl)			
	
	// Compare to actual slope to get scaled height 
	Make/O/N = (256,256) ht_extrap,ht_fit
	Make/O/N=3 w_Coef
	Duplicate/FREE ht_true ht_true_copy
	CurveFit/N/Q/NTHR=0/L=(256) poly2D 1, ht_true /D
	ht_extrap = poly2d(w_Coef,P,Q)
	ht_fit = ht_true_copy - ht_extrap
	Variable minHeight = WaveMin(ht_fit)
	ht_fit -= minHeight

	Make/O/N = (256,256) ht_difference, ht_normalized_trgt
	ht_difference = trgt_scaled - ht_fit
	Variable maxDiff = WaveMax(ht_difference)
	ht_normalized_trgt = ht_fit + maxDiff

	Make/O/N = (256,256) ht_to_dig
	ht_to_dig = ht_normalized_trgt - trgt_scaled

	Make/O/N = (256,256) v_scaled, lith_force
	Variable vslope =  (10 ^ 9) * (VMAX - VTHRESHOLD) / DIGPFR	
	v_scaled = (ht_to_dig * vslope) + VSP
	lith_force = ( (v_scaled > VSP) * (v_scaled < VMAX) * ( v_scaled ) ) + ( VMAX * (v_scaled > VMAX) ) + ( (v_scaled <= VSP) * VSP )
	
	print("mean to dig: " + num2str(mean(ht_to_dig)))
	KillWaves $filename
	return lith_force
end

Function InitCustomScan() 
	// Sends wave from GetForce(), initializes scan
	// Input this into ImageScanFinish User Callback, then call it from the command line to start experiment
	// TODO: setscale x to value from Scan Size in master pannel, figure out how to do y with width:height
	SetDataFolder root:Packages:MFP3D:XPT:Cypher
	Wave trgt_scaled
	Wave lith_force = getForce()
	
	NVAR should_we_finish = root:Packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':should_we_finish // find a time to set this to true
	NVAR total_images = root:Packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':total_images 
	if (should_we_finish>=total_images)
		ARCheckFunc("ARUserCallbackMasterCheck_1", 0)
	else
		SendInNewLithoImage(lith_force)
		should_we_finish += 1
		print("Image # " + num2str(should_we_finish))
		SetDataFolder root:Packages:MFP3D:LithoBias // CHECK TO MAKE SURE FOLDER IS RIGHT
		InitVelocityScan("VelocityDoScanButton_3")
	endif 

End		//InitCustomScan()


Function ResetExp()
	DFREF dfr = root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals'
	NVAR should_we_finish = dfr:should_we_finish
	should_we_finish = 0
End


Function/T GetFilename() // Returns name of current image file for access by GetForce()
// TODO: get format_num from master pannel instead of img_num. Base Name + last 4 digits, same format as AFM files will be

	NVAR img_num = root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':img_num
	NVAR increment_check = root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':increment_check
	SVAR base_name = root:packages:MFP3D:Main:Variables:BaseName // base_name from Base Name in Master Panel
	//SVAR base_name = root:packages:MFP3D:LithoBias:GlobalVars:'My Globals':basename
	String format_num
	sprintf format_num "%04d", img_num // Formats to 0000 digits
	String filename = base_name + format_num // func that makes a higher number at the end each time
	Printf "filename: %s\r", filename

	If(increment_check != 1)
		img_num += 1
	endif
	
	return filename
End


Function FlipExcel(pathName, fileName, worksheetName, startCell, endCell) // Do this only once before starting, to load excel wave of target pattern into experiment
	// Common Function Call: FlipExcel("G:Igor Custom Procs:Hsquared:Code", "new Comparison AFM", "nmTarget", "A1", "IV256")
    	String pathName                     // Name of Igor symbolic path or "" to get dialog
    	String fileName                         // Name of file to load or "" to get dialog
    	String worksheetName
    	String startCell                            // e.g., "B1"
    	String endCell                          // e.g., "J100"
    	String finalWave = "trgt"			// Name of the wave that will contain the info in igor memory
    	if ((strlen(pathName)==0) || (strlen(fileName)==0))
        	// Display dialog looking for file.
        	Variable refNum
        	String filters = "Excel Files (*.xls,*.xlsx,*.xlsm):.xls,.xlsx,.xlsm;"
        	filters += "All Files:.*;"
        	Open/D/R/P=$pathName /F=filters refNum as fileName
        	fileName = S_fileName               // S_fileName is set by Open/D
        	if (strlen(fileName) == 0)          // User cancelled?
            		return -2
        	endif
    	endif

    // Load row 1 into numeric waves
    	XLLoadWave/S=worksheetName/R=($startCell,$endCell)/COLT="N"/O/V=0/K=0/Q fileName
    	if (V_flag == 0)
        	return -1           // User cancelled
    	endif

    	String names = S_waveNames          // S_waveNames is created by XLLoadWave
    	//String nameOut = UniqueName(finalWave, 1, 0)
    	Concatenate/KILL/O names, $finalWave    // Create matrix and kill 1D waves
   	MatrixTranspose $finalWave
	Reverse/DIM=1/P $finalWave
    	Printf "Created numeric matrix wave %s containing cells %s to %s in worksheet \"%s\"\r", finalWave, startCell, endCell, worksheetName
	Duplicate/Free/WAVE $finalwave, OneD_trgt
	Duplicate/Free/WAVE $finalwave, TwoD_trgt
	Redimension/N=(65536) OneD_trgt
	Make/O/N = (256,256) trgt_scaled
	NVAR trgt_depth = root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':trgt_depth   // Nanometers. Difference in low and high signal in target pattern TODO
	trgt_scaled = (trgt_depth / (10^9)) * ((TwoD_trgt - waveMin(OneD_trgt)) / (waveMax(OneD_trgt) - waveMin(OneD_trgt)))

    	return 0            // Success
End


Function/WAVE IndexScale(name, range, direction) //set direction 0 for y, 1 for x
	String name
	Variable range
	Variable direction
	
	Make/O/N=(256,256) $name
	WAVE waveref = $name
	
	Variable i
	Variable j
	if (direction == 0)
		for(i=0; i < 256; i+=1)
			for(j=0; j < 256; j+=1)
				waveref[i][j] = (i / 256) * range * 10^-6
			endfor
		endfor
	else 
		for(i=0; i < 256; i+=1)
			for(j=0; j < 256; j+=1)
				waveref[j][i] = (i / 256) * range * 10^-6
			endfor
		endfor
	endif
	
	return waveref
End


Function forcePlot(lith_force)
	WAVE lith_force
	SetScale/I x 0, 5,"um", lith_force
	SetScale/I y 0, 5,"um", lith_force
	Display 
		AppendImage lith_force
		ModifyImage lith_force ctab = {*,*, Grays256, 1} 
End


Function NanoRASP_Panel() : Panel
	PauseUpdate; Silent 1		// building window...
	DFREF dfr = GetPackageDFREF()
	NewPanel /W=(744,294,1314,494) as "NanoRASP Panel"
	ModifyPanel cbRGB=(65534,65534,65534)
	Button bLoad,pos={284,49},size={100,20},proc=LoadExcelButton,title="Load Excel Data"
	SetVariable vmax,pos={302,11},size={120,18},title="vmax",font="Arial"
	SetVariable vmax,value= root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':VMAX
	SetVariable vsp,pos={164,12},size={120,18},title="vsp"
	SetVariable vsp,help={"Setpoint voltage (applied when difference=0)"}
	SetVariable vsp,font="Arial"
	SetVariable vsp,value= root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':VSP
	SetVariable vthreshold,pos={22,13},size={120,18},title="vthreshold",font="Arial"
	SetVariable vthreshold,value= root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':VTHRESHOLD
	SetVariable kval,pos={20,89},size={137,18},title="kval",font="Arial"
	SetVariable kval,value= root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':KVAL
	SetVariable dfchannel,pos={5,50},size={130,18},title="deflection channel"
	SetVariable dfchannel,font="Arial"
	SetVariable dfchannel,value= root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':DFCHANNEL
	SetVariable htchannel,pos={146,50},size={113,18},title="height channel"
	SetVariable htchannel,font="Arial"
	SetVariable htchannel,value= root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':HTCHANNEL
	SetVariable img_num,pos={214,87},size={120,18},font="Arial"
	SetVariable img_num,value= root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':img_num
	SetVariable digpfr,pos={436,10},size={120,18},font="Arial"
	SetVariable digpfr,value= root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':DIGPFR
	CheckBox IncludeDef,pos={15,117},size={147,14},title="Check to include deflection"
	CheckBox IncludeDef,value= 0
	Button bExp,pos={405,49},size={100,20},proc=ResetExpButton,title="Reset Experiment"
	Button bExp,help={"Reset the experiment"}
	Button bInit,pos={238,162},size={116,20},proc=InitButton,title="Initialize (Take Care!!)"
	Button bInit,help={"Reset the experiment"}

	SetVariable trgt_depth,pos={190,117},size={120,18},title="Target Depth"
	SetVariable trgt_depth,help={"target depth"}
	SetVariable trgt_depth,font="Arial"
	SetVariable trgt_depth,value= root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':trgt_depth

	SetVariable total_images,pos={393,85},size={120,18},title="Total Images"
	SetVariable total_images,help={"Setpoint voltage (applied when difference=0)"}
	SetVariable total_images,font="Arial"
	SetVariable total_images,value= root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':total_images
End
