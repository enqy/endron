with open("large_file.edr", "w") as f:
    f.writelines([f'@std{i};$fn,{{|import;"std"}}\n' for i in range(100000)])
