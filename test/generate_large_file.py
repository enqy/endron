with open("large_file.edr", "w") as f:
    f.writelines(['@std;$fn,{|import;"std"}\n'] * 1000000)
