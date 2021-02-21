#pragma rtGlobals=3		// Use modern global access method and strict wave access.

// TODO: 
// Integrate. Change ht_true to raw data, add in global var functionality
// Replace padding vals with global 
// Make sure sizes of all waves are correct
// I think the big problem right now is with the fit. Just doing funny things

Function ImportExcel(pathName, fileName, worksheetName, startCell, endCell) // Do this only once before starting, to load excel wave of target pattern into experiment
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
	Duplicate/O/WAVE $finalwave, OneD_trgt
	Duplicate/O/WAVE $finalwave, TwoD_trgt
	Redimension/N=(65536) OneD_trgt
	Make/O/N = (256,256) trgt_scaled
	Variable trgt_depth = 25	// Nanometers. Difference in low and high signal in target pattern TODO
	trgt_scaled = -1 * (trgt_depth / (10^9)) * ((TwoD_trgt - waveMin(OneD_trgt)) / (waveMax(OneD_trgt) - waveMin(OneD_trgt)))

    	return 0            // Success
End

Function/WAVE getIdealSlope(ht_true)
	Wave ht_true      // ht_true will be raw data for height (and possibly using deflection)
	
	variable padding = 128 // Replace with global
	Make/O/N = (512,512) plane_big
	Make/O/N=(512-2*padding, 512-2*padding) nanWave, plane_interpolated, ht_interpolated, ht_variance
	Make/O/N=3 w_Coef
	nanWave = NaN
	Duplicate/O ht_true ht_true_for_fit 
	
	expandInput(nanWave, ht_true_for_fit, padding)  // This replaces center values with NaN. Curve fitting should ignore NaN vals but keep the registries and index scaling
	CurveFit/N/Q/NTHR=0/L=(256) poly2D 1, ht_true_for_fit /D
	plane_big = poly2d(w_Coef,P,Q)
	shrinkInput(plane_big, plane_interpolated, padding) 
	shrinkInput(ht_true, ht_interpolated, padding) 

	ht_variance = ht_interpolated - plane_interpolated
	return ht_variance
end

Function/WAVE flattenSlope(ht_true)
	Wave ht_true      // ht_true will be raw data for height (and possibly using deflection)
	
	variable padding = 128
	Make/O/N=(512-2*padding, 512-2*padding) nanWave
	Make/O/N=(512,512) temporaryFlatten
	nanWave = NaN
	Duplicate/O ht_true ht_true_for_fit 
	expandInput(nanWave, ht_true_for_fit, padding)
	
	Variable ScanPoints = DimSize(ht_true,0)					//get the scanpoints
	Variable ScanLines = DimSize(ht_true,1)					//get the scanlines
	Variable Order = 1
	Variable Layer = 0
	
	Make/O/D/N=(3) ParmWave
	WaveStats/Q/R=[layer*ScanPoints*ScanLines,(layer+1)*ScanPoints*ScanLines-1]/M=1 ht_true
	ParmWave = {V_Avg,0,0}
	//ARC_SubtractPoly2D(ht_true_for_fit,ParmWave,0,1,0,1,0,DimSize(ht_true_for_fit,1)-1,Layer)
	temporaryFlatten[][0,511][Layer] = ParmWave[0]+ParmWave[1]*(P*1+0)+ParmWave[2]*(Q*1+0)
	
	ht_true -= temporaryFlatten
	return ht_true
end

Function PerformFlatten(ImageWave)
	Wave ImageWave
	
	variable padding = 128
	variable order = 1
	variable layer = 0
	Make/O/N=(512) tempParm
	Make/Free/N=(512-2*padding, 512-2*padding) zeroWave
	Make/Free/N=(512,512) tempMask
	zeroWave = 0
	tempMask = 1
	expandInput(zeroWave, tempMask, padding)
	
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

Function main()
	Wave trgt_scaled, ht_true
	Variable VMAX = 6, VTHRESHOLD = 2, DIGPFR_guess = 10, VSP = 0   // Replace with global
	Variable padding = 128 // Replace with global
	
	Make/O/N = (512-2*padding, 512-2*padding) ht_variance, v_scaled, v_limited, ht_to_dig
	performFlatten(ht_true)
	shrinkInput(ht_true, ht_variance, padding)
	
	Variable vslope =  (10 ^ 9) * (VMAX - VTHRESHOLD) / DIGPFR_guess		
	
	ht_to_dig = ht_variance - trgt_scaled
	v_scaled = (ht_to_dig * vslope) + VSP
	v_limited = ( (v_scaled > VSP) * (v_scaled < VMAX) * ( v_scaled ) ) + ( VMAX * (v_scaled > VMAX) ) + ( (v_scaled <= VSP) * VSP )
	
	Make/O/N=(512,512) lith_force
	lith_force = VSP // Initialize all values to setpoint.  
	expandInput(v_limited, lith_force, padding) // Imprint applied force using v_limited
	//return lith_force
end

Function shrinkInput(bigWave, outWave, padding)
	Wave bigWave, outWave
	Variable padding
	Variable i, j
	for (i = padding; i < 512 - padding; i+=1)
		for (j = padding; j < 512 - padding; j+=1)
			outWave[i - padding][j - padding] = bigWave[i][j]
		endfor  
	endfor  

end

Function expandInput(smallWave, outWave, padding)
	Wave smallWave, outWave
	Variable padding
	Variable i, j
	for (i = padding; i < 512 - padding; i+=1)
		for (j = padding; j < 512 - padding; j+=1)
			outWave[i][j] = smallWave[i - padding][j - padding]
		endfor  
	endfor  
end

Function simulation(lith_force, test_data, iterations)
	Wave lith_force, test_data
	Variable iterations
	Wave ht_true, ht_to_dig, mean_ht_to_dig
	Variable DIGPFR_actual = 1
	Variable i = 0
	Variable mean_height
	
	do 
		main()
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

