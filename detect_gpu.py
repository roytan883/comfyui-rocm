import subprocess
import sys
import os

# Comprehensive mapping of GPU model numbers to gfx codes
# Format: (model_list, gfx_code, architecture_name, supported)
GPU_TO_GFX = [
    # RDNA4 (gfx12xx)
    (['rx 9060'], 'gfx1200', 'RDNA 4', True),
    (['rx 9070', 'r9700', 'r9600'], 'gfx1201', 'RDNA 4', True),
    (['gfx12-0'], 'gfx12-0', 'RDNA 4', True),
    
    # RDNA3.5 (gfx115x)
    (['890m'], 'gfx1150', 'Strix Point', True),
    (['8060s', '8050s', '8040s', '880m'], 'gfx1151', 'Strix Halo', True),
    (['860m', '840m', '820m'], 'gfx1152', 'Krackan Point', True),
    (['gfx1153'], 'gfx1153', 'RDNA 3.5', True),
    
    # RDNA3 (gfx110x)
    (['rx 7900', 'w7900', 'w7800'], 'gfx1100', 'RDNA 3', True),
    (['rx 7800', 'rx 7700', 'w7700'], 'gfx1101', 'RDNA 3', True),
    (['rx 7700s', 'rx 7650', 'rx 7600', 'w7600', 'w7500', 'rx 7400', 'w7400'], 'gfx1102', 'RDNA 3', True),
    (['780m', '760m', '740m'], 'gfx1103', 'RDNA 3', True),
       
    # RDNA2 (gfx103x)
    (['rx 6950', 'rx 6900', 'rx 6800', 'w6800', 'v620'], 'gfx1030', 'RDNA 2', True),
    (['rx 6750', 'rx 6700', 'rx 6800m', 'rx 6700m', 'rx 6800s', 'rx 6700s'], 'gfx1031', 'RDNA 2', True),
    (['rx 6650', 'rx 6600', 'w6600', 'rx 6650m', 'rx 6600m', 'rx 6600s'], 'gfx1032', 'RDNA 2', True),
    (['rx 6500', 'w6500', 'rx 6500m'], 'gfx1034', 'RDNA 2', True),
    (['680m', '660m'], 'gfx1035', 'RDNA 2', True),
    (['610m'], 'gfx1036', 'RDNA 2', True),
    (['rx 6550', 'rx 6450', 'rx 6400', 'w6400', 'rx 6300', 'w6300'], 'gfx1033', 'RDNA 2', True),

    # RDNA1 (gfx101x)
    (['rx 5700', 'rx 5600'], 'gfx1010', 'RDNA 1', True),
    (['rx 5500', 'radeon pro v520'], 'gfx1011', 'RDNA 1', True),
    
    # Data Center / Enterprise GPUs
    (['radeon pro vii'], 'gfx90X', 'Radeon Pro VII', True),
    (['mi300a', 'mi300x', 'mi325x'], 'gfx942', 'MI300/MI325', True),  # Now supported via legacy URL
    (['mi350x', 'mi355x'], 'gfx950', 'MI350/MI355', True),  # Now supported via legacy URL

    # GCN5 / Vega (gfx900/906/908/90a)
    (['rx vega', 'vega 64', 'vega 56', 'vega frontier'], 'gfx900', 'Vega 10 / GCN5', True),
    (['radeon vii', 'vega 20'], 'gfx906', 'Vega 20 / GCN5', True),
    (['instinct mi100'], 'gfx908', 'Arcturus / MI100', True),
    (['instinct mi200', 'instinct mi210', 'instinct mi250'], 'gfx90a', 'Aldebaran / MI200', True),
]

def detect_gpu_wmic():
    try:
        result = subprocess.run(
            ['wmic', 'path', 'win32_videocontroller', 'get', 'name'],
            capture_output=True,
            text=True,
            check=False,
            timeout=10
        )
        
        if result.returncode == 0:
            gpu_list = result.stdout.strip().split('\n')
            amd_gpus = []
            for gpu in gpu_list:
                gpu = gpu.strip()
                if gpu and gpu != "Name" and "AMD" in gpu and "Radeon" in gpu:
                    amd_gpus.append(gpu)
            return amd_gpus
    except (FileNotFoundError, subprocess.TimeoutExpired, Exception):
        pass
    return []

def detect_gpu_powershell():
    try:
        ps_command = "Get-WmiObject Win32_VideoController | Select-Object -ExpandProperty Name"
        result = subprocess.run(
            ['powershell', '-NoProfile', '-Command', ps_command],
            capture_output=True,
            text=True,
            check=False,
            timeout=10
        )
        
        if result.returncode == 0:
            gpu_list = result.stdout.strip().split('\n')
            amd_gpus = []
            for gpu in gpu_list:
                gpu = gpu.strip()
                if gpu and "AMD" in gpu and "Radeon" in gpu:
                    amd_gpus.append(gpu)
            return amd_gpus
    except (FileNotFoundError, subprocess.TimeoutExpired, Exception):
        pass
    return []

def match_gpu_to_gfx(gpu_name):
    gpu_lower = gpu_name.lower()
    
    for model_list, gfx, arch_name, supported in GPU_TO_GFX:
        for model in model_list:
            if model in gpu_lower:
                return gfx, arch_name, supported
    
    return None, None, False

def detect_gpu():
    print("Attempting to detect AMD GPU...")
    
    # Try different detection methods in order of preference
    amd_gpus = []
    
    # Method 1: wmic (fast and works on most systems)
    print("Trying wmic method...")
    amd_gpus = detect_gpu_wmic()
    
    # Method 2: PowerShell (works on all modern Windows)
    if not amd_gpus:
        print("Trying PowerShell method...")
        amd_gpus = detect_gpu_powershell()
    
    if not amd_gpus:
        print("No AMD GPU detected")
        print("If you have an AMD GPU, please ensure your drivers are installed.")
        return None
    
    # Process detected GPUs
    print(f"\nFound {len(amd_gpus)} AMD GPU(s):")
    for gpu in amd_gpus:
        print(f"  - {gpu}")
    
    # Try to match to known architectures
    for gpu in amd_gpus:
        gfx, arch_name, supported = match_gpu_to_gfx(gpu)
        
        if gfx and supported:
            print(f"\nMatched GPU: {gpu}")
            print(f"Architecture: {arch_name} ({gfx})")
            print("Status: SUPPORTED")
            return gfx
        elif gfx and not supported:
            print(f"\nMatched GPU: {gpu}")
            print(f"Architecture: {arch_name} ({gfx})")
            print("Status: NOT YET SUPPORTED - Coming in future updates")
            return None
    
    # If we found AMD GPUs but couldn't match them
    print("\nGPU(s) found but architecture could not be identified.")
    print("Only GCN, Vega, RDNA1, RDNA2, RDNA3, and RDNA4 architectures are supported.")
    print("Please check if your GPU is compatible with ROCm.")
    return None

if __name__ == "__main__":
    try:
        gfx = detect_gpu()
        if gfx:
            print(f"\n{gfx}")
            sys.exit(0)
        else:
            sys.exit(1)
    except Exception as e:
        print(f"Fatal error during GPU detection: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
