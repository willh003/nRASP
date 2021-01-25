#pragma rtGlobals=3        // Use strict wave reference mode

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
	Duplicate/O/WAVE $finalwave, OneD_trgt
	Duplicate/O/WAVE $finalwave, TwoD_trgt
	Redimension/N=(65536) OneD_trgt
	Make/O/N = (256,256) trgt_scaled
	Variable trgt_depth = 25	// Nanometers. Difference in low and high signal in target pattern TODO
	trgt_scaled = (trgt_depth / (10^9)) * ((TwoD_trgt - waveMin(OneD_trgt)) / (waveMax(OneD_trgt) - waveMin(OneD_trgt)))

    	return 0            // Success
End

Function fit(ht_true)
	wave ht_true
 
	Make/O/N = (256,256) ht_extrap,ht_fit
	Make/O/N=3 w_Coef
	Duplicate/FREE ht_true ht_true_copy
	CurveFit/N/Q/NTHR=0/L=(256) poly2D 1, ht_true /D
	ht_extrap = poly2d(w_Coef,P,Q)
	ht_fit = ht_true_copy - ht_extrap
	
	//Variable minHeight = WaveMin(ht_fit)
//	ht_fit -= minHeight

end

Function normalize(ht_fit, trgt_scaled)
	wave ht_fit, trgt_scaled
	Make/O/N = (256,256) ht_difference, ht_normalized_trgt
	ht_difference = trgt_scaled - ht_fit
	Variable maxDiff = WaveMax(ht_difference)
	ht_normalized_trgt = ht_fit + maxDiff
end

Function getToDig(ht_normalized_trgt, trgt_scaled)
	wave ht_normalized_trgt, trgt_scaled
	Make/O/N = (256,256) ht_to_dig
	ht_to_dig = ht_normalized_trgt - trgt_scaled
end

Function scaleForce(ht_to_dig)
	Wave ht_to_dig
	Make/O/N = (256,256) v_scaled, lith_force
	Variable VMAX = 6, VTHRESHOLD = 2, DIGPFR_guess = 10, VSP = 1
	Variable vslope =  (10 ^ 9) * (VMAX - VTHRESHOLD) / DIGPFR_guess		
	v_scaled = (ht_to_dig * vslope) + VSP
	lith_force = ( (v_scaled > VSP) * (v_scaled < VMAX) * ( v_scaled ) ) + ( VMAX * (v_scaled > VMAX) ) + ( (v_scaled <= VSP) * VSP )
end

Function getForce(ht_true, trgt_scaled)
	Wave ht_true, trgt_scaled
	Wave ht_fit, ht_normalized_trgt, ht_to_dig, lith_force
	
	fit(ht_true)
	normalize(ht_fit, trgt_scaled)
	getToDig(ht_normalized_trgt, trgt_scaled)
	scaleForce(ht_to_dig)
end

Function simulateDig(lith_force, test_data, iterations)
	Wave lith_force, test_data
	Variable iterations
	Wave trgt_scaled, ht_to_dig, mean_ht_to_dig
	Variable DIGPFR_actual = 1
	Variable i = 0
	Variable mean_height
	
	do 
		getForce(test_data, trgt_scaled)
		test_data -= lith_force * DIGPFR_actual / (10^9)
		mean_height =  mean(ht_to_dig)
		redimension/n = (i + 1) mean_ht_to_dig
		mean_ht_to_dig[i] = mean_height
		print("mean to dig on trial " + num2str(i + 1) + ": " + num2str(mean_height))
		print("max to dig on trial " + num2str(i + 1) + ": " + num2str(waveMax(ht_to_dig)))
		i += 1
	while (i < iterations)
end


Function resetSim()
	wave test
	duplicate/o test, test_data
end