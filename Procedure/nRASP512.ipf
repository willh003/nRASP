#Ifdef ARrtGlobals
#pragma rtGlobals=1        // Use modern global access method.
#else
#pragma rtGlobals=3        // Use strict wave reference mode
#endif 
#include ":AsylumResearch:Code3D:Initialization"
#include ":AsylumResearch:Code3D:MotorControl"
#include ":AsylumResearch:Code3D:Environ"

// TODO: 
// Maybe do something to remove bumps at the start
// i.e. normalize everything above zero for the first

Override Function/S LithoDriveDAC(TipParms)
        Struct ARTipHolderParms &TipParms
        return "$HeightLoop.Setpoint"
End //

Function InitCustomScan() 
	// Sends wave from GetForce(), initializes scan
	// Input this into ImageLastScan User Callback, then call it from the command line to start experiment
	// TODO: setscale x to value from Scan Size in master pannel, figure out how to do y with width:height
	SetDataFolder root:Packages:MFP3D:XPT:Cypher
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
		InitVelocityScan("VelocityDoDownScanButton_3")
	endif 

End		//InitCustomScan()

Function/WAVE getForce()
	SetDataFolder root:Packages:MFP3D:XPT:Cypher
	getCurrentHeight()
	Wave trgt_scaled, ht_true, mean_ht_to_dig
	
	DFREF dfr = root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals'
	NVAR DIGPFR = dfr:DIGPFR			// Size of interval of heights (in nm) where voltage will start converging. Smaller = more gradient in lith_force
	NVAR VTHRESHOLD = dfr:VTHRESHOLD	// Voltage at which it starts actually digging
	NVAR VMAX = dfr:VMAX				// Max voltage allowed
	NVAR VSP = dfr:VSP					// Setpoint voltage (what to apply when diff = 0)
	NVAR padding = dfr:padding  // Size of border around digging (pixels)
	NVAR X_DRIFT = dfr:X_DRIFT
	NVAR Y_DRIFT = dfr:Y_DRIFT
	
	Variable vslope =  (10 ^ 9) * (VMAX - VTHRESHOLD) / DIGPFR	
	print(num2str(512-2*padding))
	Make/O/N = (512-2*padding, 512) ht_variance, v_scaled, v_corrected, v_limited, ht_to_dig
	performFlatten(ht_true)
	shrinkInput(ht_true, ht_variance, padding)
	
	print(num2str(vslope))
	ht_to_dig = ht_variance - trgt_scaled
	v_scaled = (ht_to_dig * vslope) + VSP
	v_limited = ( (v_scaled > VTHRESHOLD) * (v_scaled < VMAX) * ( v_scaled ) ) + ( VMAX * (v_scaled >= VMAX) ) + ( (v_scaled <= VTHRESHOLD) * VSP )
	
	variable mean_to_dig = mean(ht_to_dig)
	redimension/n = (dimsize(mean_ht_to_dig, 0) + 1) mean_ht_to_dig
	mean_ht_to_dig[dimsize(mean_ht_to_dig, 0) - 1] = mean_to_dig
	print("mean to dig: " + num2str(mean_to_dig))

	v_corrected = VSP
	verticalShift(v_limited, v_corrected, padding, Y_DRIFT)		// v_limited is shifted up or down, outputting v_corrected
	// Y_DRIFT should be positive if shadows are on the bottom, neg if on top

	Make/O/N=(512,512) lith_force
	lith_force = VSP // Initialize all values to setpoint.  
	expandInput(v_corrected, lith_force, padding, X_DRIFT) // Imprint applied force using v_limited
	// X_DRIFT should be positive if shadows to the left, neg if shadows to the right
	return lith_force
end

Function getCurrentHeight()
	
	DFREF dfr = root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals'
	NVAR KVAL = dfr:KVAL				// Scalar for deflection
	NVAR DFCHANNEL = dfr:DFCHANNEL		// Channel containing defl data
	NVAR HTCHANNEL = dfr:HTCHANNEL		// Channel containing ht data
	
	Make/O/N = (512, 512) lith_current_all, lith_ht, lith_defl
	Make/O/N = (512, 512) ht_true
	String filename = GetFilename()	
	String indexString = GS("SaveImage")
	NewPath/O folderpath, indexstring  	// folderpath is the symbolic path to the data folder specified in the master pannel
	LoadWave/M/O/B="C=256, N=current1;"/P=folderpath, filename // This should be final call for loading the file
	
	// Copy loaded wave to lith_current_all
	Duplicate/O/WAVE $filename, $"lith_current_all" // $ is necessary because of how IGOR loops/duplicates stuff
	lith_ht[][] = lith_current_all[x][y][HTCHANNEL]
	lith_defl[][] = lith_current_all[x][y][DFCHANNEL]
	Reverse/DIM=1/P lith_ht 		// We realized the saved height and deflection data are flipped vertically w/r the images (top at the bottom).
	Reverse/DIM=1/P lith_defl
	ht_true = lith_ht  + (KVAL * lith_defl)
	KillWaves $filename
End

Function PerformFlatten(ImageWave)
	Wave ImageWave
	
	DFREF dfr = root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals'
	NVAR padding = dfr:padding
	variable order = 1
	variable layer = 0
	Make/Free/N=(512) tempParm
	Make/Free/N=(512-2*padding, 512) zeroWave
	Make/Free/N=(512,512) tempMask
	zeroWave = 0
	tempMask = 1
	expandInput(zeroWave, tempMask, padding, 0)
	
	HHMaskedFlatten(ImageWave,order,layer,TempParm,tempMask)

end

Function HHMaskedFlatten(ImageWave,order,layer,TempParm,tempMask)
	Wave ImageWave
	Variable order
	Variable layer
	Wave TempParm
	Wave tempMask

	Variable output = 0
	variable points = DimSize(ImageWave,0)
	variable lines = DimSIze(ImageWave,1)
	variable i
	Variable minCount = Limit(points*.1,4,10)		//MinCount is from 4 to 10.
	
	switch (order)
		case 0:								//just take out the offset

			Make/O/N=(points,lines) tempWave	//make a temp wave
			tempWave = ImageWave[p][q][layer]
			tempWave /= tempMask					//this changes the mask=0 points to Inf, so they aren't used in the WaveStats
			for (i = 0;i < lines;i += 1)		//loop until all the lines are done
				WaveStats/M=1/Q/R=[(i*points),(i+1)*points-1] tempWave	//do wavestats for one line
				if (!IsNaN(V_avg))					//check if this is a number, not just NaN
					ImageWave[][i][layer] -= V_avg		//subtract the offset
				endif
				TempParm[I][0] = V_Avg
			endfor

			break
		
		case 1:								// take out slope, offset
			Make/O/N=(points)/FREE LineWave, LineMask
			CopyScales/P ImageWave LineWave, LineMask		//copy the x scaling
			Make/O/N=(order+1)/D W_coef
			for (i = 0;i < lines;i += 1)				//loop through all of the lines
				LineWave = ImageWave[p][i][layer]					//copy the line into LineWave
				LineMask = tempMask[p][i]						//copy the line from the mask
				if (sum(LineMask,leftx(LineMask),rightx(LineMask)) > minCount)		//make sure that there are at least 10 points
					CurveFit/Q/N line LineWave /M=LineMask	//do a line fit using the mask
					ImageWave[][i][layer] -= poly(W_coef,x)			//subtract the poly fit from each line
					TempParm[I][] = W_Coef[Q]
				else											//if there are not 10 unmasked points
					WaveStats/Q/M=1 LineWave
					ImageWave[][i][layer] -= V_avg			//then just subtract the average
					TempParm[I][0] = V_avg
				endif
			endfor

			//KillWaves/Z LineWave, LineMask, w_coef				//kill the temp waves
			break
	endswitch
	Return output
End // HHMaskedFlatten


Function shrinkInput(bigWave, outWave, padding)  // Take middle values from 512x512 wave (based on border size)
	Wave bigWave, outWave
	Variable padding
	Duplicate/O bigWave outWave

	deletepoints/M=0 512 - padding, padding, outWave
	deletepoints/M=0 0, padding, outWave
end

function expandInput(smallWave, outWave, padding, shiftRight)
	wave smallWave, outWave
	variable padding, shiftRight
	variable i, j

	for (i = padding; i < 512 - padding; i+=1)
		for (j = 0; j < 512; j+=1)
			outWave[i + shiftRight][j] = smallWave[i - padding][j]
		endfor
	endfor	
end

function verticalShift(w, r, padding, yShift)		// Positive yShift adds rows at bottom, deletes from top (shift up). Negative deletes from bottom and adds to top (shift down)
	wave w, r
	variable padding, yShift
	
	variable i, j
	if (yShift < 0)
		for (i = 0; i < 512 + yShift; i+=1) // Add yshift because it is negative
			for (j=0; j < 512 - 2*padding; j+=1)
				r[j][i] = w[j][i-yShift]
			endfor
		endfor
	elseif (yShift > 0)
		for (i = yShift; i < 512; i+=1)
			for (j=0; j < 512 - 2*padding; j+=1)
				r[j][i] = w[j][i-yShift]
			endfor
		endfor
	else
		r = w
	endif
end

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

Function ImportExcel(pathName, fileName, worksheetName, startCell, endCell) // Do this only once before starting, to load excel wave of target pattern into experiment
	// Import an excel spreadsheet with 512 rows, 256 cols (or more cols if more padding)
	// Common Function Call: FlipExcel("G:Igor Custom Procs:Hsquared:Code", "new Comparison AFM", "nmTarget", "A1", "IV256")
    	String pathName                     // Name of Igor symbolic path or "" to get dialog
    	String fileName                         // Name of file to load or "" to get dialog
    	String worksheetName
    	String startCell                            // e.g., "B1"
    	String endCell                          // e.g., "J100"
    	String finalWave = "trgt"			// Name of the wave that will contain the info in igor memory
    	SetDataFolder root:Packages:MFP3D:XPT:Cypher
    	DFREF dfr = root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals'
	NVAR padding = dfr:padding
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
//	Reverse/DIM=1/P $finalWave
	Duplicate/O/WAVE $finalwave, OneD_trgt
	Duplicate/O/WAVE $finalwave, TwoD_trgt
	Redimension/N=((512-2*padding)*512) OneD_trgt
	Make/O/N = (512-2*padding,512) trgt_scaled
	NVAR trgt_depth = root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':trgt_depth   // Nanometers. Difference in low and high signal in target pattern TODO
	trgt_scaled = -1 * (trgt_depth / (10^9)) * ((TwoD_trgt - waveMin(OneD_trgt)) / (waveMax(OneD_trgt) - waveMin(OneD_trgt)))
	make/o/n=0 mean_ht_to_dig
	Printf "Created numeric matrix wave %s containing cells %s to %s in worksheet \"%s\"\r", finalWave, startCell, endCell, worksheetName
    	return 0            // Success
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
	Variable/G dfr:DIGPFR= 10	// Nm per frame at VMAX
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
	Variable/G dfr:padding = 128
	Variable/G dfr:X_DRIFT = 0
	Variable/G dfr:Y_DRIFT = 0
	Variable/G dfr:VPRECONTACT = -1
	return dfr
End

Function/DF GetPackageDFREF()
	DFREF dfr = root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals'
	if (DataFolderRefStatus(dfr) != 1) // Data folder does not exist?
		DFREF dfr = CreatePackageData() // Create package data folder
	endif
	return dfr
End

Function ResetExp()
	DFREF dfr = root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals'
	NVAR should_we_finish = dfr:should_we_finish
	should_we_finish = 0
	SetDataFolder root:Packages:MFP3D:XPT:Cypher
	make/o/n=0 mean_ht_to_dig
	ARCheckFunc("ARUserCallbackMasterCheck_1", 1)
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
				ImportExcel("","","","A1","IV512")
			endif
		break
	endswitch
	return 0
End

Function InitButton(ba) : ButtonControl // Handles Reset Experiment queries
	STRUCT WMButtonAction &ba
	switch(ba.eventCode)
		case 2: // Mouse up
			if (CmpStr(ba.ctrlName,"bInit") == 0)
				InitCustomScan()
			endif
		break
	endswitch
	return 0
End

Function MakeGraphsButton(ba) : ButtonControl // Handles Reset Experiment queries
	STRUCT WMButtonAction &ba
	switch(ba.eventCode)
		case 2: // Mouse up
			if (CmpStr(ba.ctrlName,"bGraph") == 0)
				MakeGraphs()
			endif
		break
	endswitch
	return 0
End

Menu "Macros" // Put panel in Macros menu
	"nanoRASP Panel", NanoRASP_Panel()
End

Function NanoRASP_Panel() : Panel
	PauseUpdate; Silent 1		// building window...
	DFREF dfr = GetPackageDFREF()
	NewPanel /W=(730,94,1347,363) as "NanoRASP Panel"
	ModifyPanel cbRGB=(65534,65534,65534), frameStyle=4, frameInset=3
	ShowTools/A
	SetDrawLayer UserBack
	SetDrawEnv fsize= 16
//	TabControl InitSettings
	//DrawText 256,32,"NanoRASP Panel"
	DrawText 153,53,"Hover over values for more info, or see NRASP documentation"
	Button bLoad,pos={205,68},size={100,20},proc=LoadExcelButton,title="Load Excel Pattern"
	SetVariable vmax,pos={318,104},size={120,18},title="Vmax",font="Arial"
	SetVariable vmax,value= root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':VMAX
	SetVariable vsp,pos={180,105},size={120,18},title="Vsp"
	SetVariable vsp,help={"Setpoint voltage (applied when difference=0)"}
	SetVariable vsp,font="Arial"
	SetVariable vsp,value= root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':VSP
	
		SetVariable Vprecontact,pos={200,105},size={120,18},title="Vprecontact"
	SetVariable Vprecontact,help={"Setpoint voltage (applied when difference=0)"}
	SetVariable Vprecontact,font="Arial"
	SetVariable Vprecontact,value= root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':VPRECONTACT
	
	SetVariable vthreshold,pos={38,106},size={120,18},title="Vthreshold"
	SetVariable vthreshold,font="Arial"
	SetVariable vthreshold,value= root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':VTHRESHOLD
	SetVariable kval,pos={36,142},size={137,18},title="ratio real:preset invols",font="Arial"
	SetVariable kval,value= root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':KVAL
	SetVariable dfchannel,pos={319,180},size={130,18},title="deflection channel"
	SetVariable dfchannel,font="Arial"
	SetVariable dfchannel,value= root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':DFCHANNEL
	SetVariable htchannel,pos={463,180},size={113,18},title="height channel"
	SetVariable htchannel,font="Arial"
	SetVariable htchannel,value= root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':HTCHANNEL
	SetVariable img_num,pos={35,180},size={120,18},font="Arial",title="Current nRASP Step"
	SetVariable img_num,value= root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':img_num
	SetVariable digpfr,pos={452,103},size={120,18},font="Arial", title="dig per V per frame (nm)"
	SetVariable digpfr,value= root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':DIGPFR
	Button bExp,pos={326,68},size={100,20},proc=ResetExpButton,title="New nRASP Pattern"
	Button bExp,help={"Reset the experiment"}
	Button bInit,pos={257,221},size={168,20},proc=InitButton,title="Start nRASP Scan (1st Close Data Browser!!)"
	Button bInit,help={"Reset the experiment"}
	Button bGraph,pos={305,68},size={100,20},proc=MakeGraphsButton,title="Make force, target graphs"
	
	SetVariable trgt_depth,pos={178,142},size={120,18},title="Target Depth"
	SetVariable trgt_depth,help={"target depth"},font="Arial"
	SetVariable trgt_depth,value= root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':trgt_depth
	SetVariable total_images,pos={187,180},size={120,18},title="Total Images"
	SetVariable total_images,help={"Setpoint voltage (applied when difference=0)"}
	SetVariable total_images,font="Arial"
	SetVariable total_images,value= root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':total_images
	SetVariable padding,pos={450,142},size={150,16},title="Pad Width (px each side)"
	SetVariable padding,help={"Border size around where force is applied (pixels)"},font="Arial"
	SetVariable padding,value= root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':padding
	SetVariable xdrift,pos={300,142},size={150,16},title="X Drift (px)"
	SetVariable xdrift,help={"Horizontal offset due to tip drift"},font="Arial"
	SetVariable xdrift,value= root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':X_DRIFT
	
	SetVariable ydrift,pos={36,220},size={150,16},title="Y Drift (px)"
	SetVariable ydrift,help={"Vertical offset due to tip drift"},font="Arial"
	SetVariable ydrift,value= root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals':Y_DRIFT
End

Function makeGraphPanel() : Panel
	PauseUpdate; Silent 1		// building window...
	DFREF dfr = GetPackageDFREF()
	NewPanel /W=(730,94,1347,363) as "trgt_scaled & lith_force"
	ModifyPanel cbRGB=(65534,65534,65534), frameStyle=4, frameInset=3
	ShowTools/A
	SetDrawLayer UserBack
	SetDrawEnv fsize= 16
	
	wave lith_force, trgt_scaled
	duplicate/o lith_force, lith_force_TOGRAPH
	duplicate/o trgt_scaled, trgt_scaled_TOGRAPH
	
	Reverse/DIM=1/P lith_force_TOGRAPH, trgt_scaled_TOGRAPH
	DFREF dfr = root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals'
	NVAR VMAX = dfr:VMAX				// Max voltage allowed
	NVAR VSP = dfr:VSP					// Setpoint voltage (what to apply when diff = 0)
	lith_force_TOGRAPH[511][511] = VMAX
	lith_force_TOGRAPH[511][510] = VSP

	appendimage lith_force_TOGRAPH
	 appendimage trgt_scaled_TOGRAPH
End

Function makeGraphs()
	Wave lith_force, trgt_scaled
	duplicate/o lith_force, lith_force_TOGRAPH
	duplicate/o trgt_scaled, trgt_scaled_TOGRAPH
	
	Reverse/DIM=1/P lith_force_TOGRAPH, trgt_scaled_TOGRAPH
	DFREF dfr = root:packages:MFP3D:XPT:Cypher:GlobalVars:'My Globals'
	NVAR VMAX = dfr:VMAX				// Max voltage allowed
	NVAR VSP = dfr:VSP					// Setpoint voltage (what to apply when diff = 0)
	lith_force_TOGRAPH[511][511] = VMAX
	lith_force_TOGRAPH[511][510] = VSP

	display/N=Force_to_be_applied; appendimage lith_force_TOGRAPH
	display/N=Target_image; appendimage trgt_scaled_TOGRAPH
	
End


Function simulation(lith_force, test_data, iterations)
	Wave lith_force, test_data
	Variable iterations
	Wave ht_true, ht_to_dig, mean_ht_to_dig
	Variable DIGPFR_actual = 1
	Variable i = 0
	Variable mean_height
	
	do 
		getForce()
		test_data -= lith_force * DIGPFR_actual / (10^9)
		mean_height =  mean(ht_to_dig)
		redimension/n = (i + 1) mean_ht_to_dig
		mean_ht_to_dig[i] = mean_height
		print("mean to dig on trial " + num2str(i + 1) + ": " + num2str(mean_height))
		print("max to dig on trial " + num2str(i + 1) + ": " + num2str(waveMax(ht_to_dig)))
		i += 1
	while (i < iterations)
end

Function reset()
	wave test
	duplicate/o test, ht_true
end


function editstructures_w()
	Struct WMSetvariableAction f
	f.SVAL = "initcustomscan()"
	f.EventCode = 1
	f.ctrlName = "ARUserCallbackImageDoneSetVar_1"
	ARCallbackSetVarFunc(f)
end


