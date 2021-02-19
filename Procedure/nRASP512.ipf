#pragma rtGlobals=3		// Use modern global access method and strict wave access.


Function/WAVE getIdealSlope()
	Make/Free/N=(512,512) ht_slope
	Wave ht_true      // ht_true will be resized raw data (using shrinkInput)
	ht_slope = ht_true
//	getMask()

	Wave resized_slope = shrinkInput(ht_slope, 128)
	return resized_slope
end

Function/WAVE getDifference()
	Make/O/N=(256,256) ht_normalized
	Wave resized_slope = getIdealSlope()
	Wave ht_true
	ht_normalized = ht_true - resized_slope
	return ht_normalized
end

Function/WAVE main(trgt)
	Wave trgt
	Wave ht_normalized = getDifference()
	Make/O/N = (256,256) v_scaled, v_limited, ht_to_dig
	Variable VMAX = 6, VTHRESHOLD = 2, DIGPFR_guess = 10, VSP = 1	   // REPLACE WITH GLOBAL
	Variable vslope =  (10 ^ 9) * (VMAX - VTHRESHOLD) / DIGPFR_guess		
	ht_to_dig = ht_normalized - trgt
	v_scaled = (ht_to_dig * vslope) + VSP
	v_limited = ( (v_scaled > VSP) * (v_scaled < VMAX) * ( v_scaled ) ) + ( VMAX * (v_scaled > VMAX) ) + ( (v_scaled <= VSP) * VSP )
	
	Wave lith_force = expandInput(v_limited, 128)
	return lith_force
end

Function/Wave shrinkInput(bigWave, padding)
	Wave bigWave
	Variable padding
	Make/Free/N=(256,256) smallWave
	Variable i, j
	for (i = padding; i < 512 - padding; i+=1)
		for (j = padding; j < 512 - padding; j+=1)
			smallWave[i - padding][j - padding] = bigWave[i][j]
		endfor  
	endfor  
	return smallWave
end

Function/Wave expandInput(smallWave, padding)
	Wave smallWave
	Variable padding
	Variable VSP = 1	// REPLACE WITH GLOBAL
	Make/O/N=(512,512) bigWave
	bigWave = VSP
	Variable i, j
	for (i = padding; i < 512 - padding; i+=1)
		for (j = padding; j < 512 - padding; j+=1)
			bigWave[i][j] = smallWave[i - padding][j - padding]
		endfor  
	endfor  
	return bigWave
end


//Function getForce()


//end
