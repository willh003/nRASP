#pragma rtGlobals=3		// Use modern global access method and strict wave access.

// TODO: 
// Integrate. Change ht_true to raw data, add in global var functionality
// Replace padding vals with global 
// Make sure sizes of all waves are correct

Function/WAVE getIdealSlope()
	Wave ht_true      // ht_true will be raw data for height (and possibly using deflection)
	
	variable padding = 128 // Replace with global
	Make/O/N = (512,512) plane_big
	Make/O/N=(512-2*padding, 512-2*padding) nanWave, plane_interpolated, ht_variance
	Make/O/N=3 w_Coef
	nanWave = NaN
	Duplicate/O ht_true ht_true_for_fit
	expandInput(nanWave, ht_true_for_fit, padding)  // This replaces center values with NaN. Curve fitting should ignore NaN vals but keep the registries and index scaling
	CurveFit/N/Q/NTHR=0/L=(256) poly2D 1, ht_true_for_fit /D
	plane_big = poly2d(w_Coef,P,Q)
	shrinkInput(plane_big, plane_interpolated, padding) 

	ht_variance = ht_true - plane_interpolated
	return ht_variance
end

Function/WAVE main(trgt)
	Wave trgt
	
	Variable VMAX = 6, VTHRESHOLD = 2, DIGPFR_guess = 10, VSP = 1	   // Replace with global
	Variable padding = 128 // Replace with global
	
	Make/O/N = (512-2*padding, 512-2*padding) v_scaled, v_limited, ht_to_dig
	Wave ht_variance = getIdealSlope()
	Variable vslope =  (10 ^ 9) * (VMAX - VTHRESHOLD) / DIGPFR_guess		
	
	ht_to_dig = ht_variance - trgt
	v_scaled = (ht_to_dig * vslope) + VSP
	v_limited = ( (v_scaled > VSP) * (v_scaled < VMAX) * ( v_scaled ) ) + ( VMAX * (v_scaled > VMAX) ) + ( (v_scaled <= VSP) * VSP )
	
	Make/O/N=(512,512) lith_force
	expandInput(v_limited, lith_force, padding) 
	return lith_force
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
	Variable VSP = 1	// REPLACE WITH GLOBAL
	outWave = VSP
	Variable i, j
	for (i = padding; i < 512 - padding; i+=1)
		for (j = padding; j < 512 - padding; j+=1)
			outWave[i][j] = smallWave[i - padding][j - padding]
		endfor  
	endfor  
end

