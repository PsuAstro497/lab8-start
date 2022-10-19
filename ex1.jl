### A Pluto.jl notebook ###
# v0.19.12

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
end

# ╔═╡ ac87ced2-986f-4e6c-80b2-104b25c171c2
begin
	using CSV, JLD2, FITSIO, FileIO 
	using DataFrames 
	using InlineStrings, OrderedCollections
	using Plots
	using PlutoUI, PlutoTeachingTools
end

# ╔═╡ e0e60e09-3808-4d6b-a773-6ba59c02f517
md"""
# File I/O & File Formats
**Astro 497, Lab 8, Exercise 1**
"""

# ╔═╡ 4745a620-5650-4c83-b4c2-9ab4572bcb66
TableOfContents()

# ╔═╡ 8c1d81ab-d215-4972-afeb-7e00bf6063c2
md"""
For many applications, its important that we be able to read input data from a file and/or to write our outputes to files so they can be reused later.  Disk access is typically *much* slower than accessing data from a system's main memory (RAM).  Therefore, disk access can easily become the limiting factor for a project.  In this set of exercises, you'll see examples of how to perform basic file I/O.  You'll also get to compare how much disk space and time is required by different file formats.  In order to compare performance using different file forms, you'll first learn how to benchmark your code.
"""

# ╔═╡ 7e132d9d-a159-4973-b8a3-36abda56249a
md"""
# Benchmarking
As you start working on larger projects, you're likely to encounter a time when you wish your code didn't take so long to run.  
When that happens, one of the first steps is to find out what steps are taking a significant portion of the run time (and which steps are so fast that there's no point in trying to speed them up).  
Two key techniques are **benchmarking** and **profiling**.  
Benchmarking is simply timing how long a program or chunck of code takes to run.  
Profiling involves keeping track of how long every line of code takes to run (or at an even finer scale).  
Julia has powerful built-in [profiling tools](https://docs.julialang.org/en/v1/manual/profile/).  There are multiples packages that can help one interpret the results from Julia's profiler. 

Here, we'll stick to simple benchmarking, using macros like, `@elapsed` and `@time`.
`@elapsed` reports how long the following line of code took to run.
`@time` provides additional useful information about how many memory allocations were performed (since unnecessary memory allocations are often a significant cause of slow code).

We'll demonstrate below using a simple function to estimate π using Monte Carlo integration (a simple, but very inefficient method for estimating π).
"""

# ╔═╡ 5be68976-141c-47f9-b2ad-1c457bb434eb
function estimate_pi(n::Integer)
	sum( rand(n).^2 .+ rand(n).^2 .<=1 )*4/n
end

# ╔═╡ fc15fc5e-0fe9-4468-9af3-e389b16b455c
@time estimate_pi(10_000) 

# ╔═╡ c80b32e9-53f1-4027-a878-f949a7acea41
md"""
The time macro prints both the total runtime, as well as information about the number of allocations (i.e., how many times the computer needed to allocate memory from "the heap") and the amount of memory allocated.  
In some cases, you may see additional information about how much time was spent on "garbage collection" (deferred work of making memory space not longer being used avaliable again) or compilation (necessary the first time a function is called for a given set of function argument types).
`@time` can be useful when we want to understand why step is slower than we anticipated.  (E.g., in this case, we're allocated memory for an array inside the sum function).
When we want to time many different function calls and store the results, `@elapsed` is useful.  For example, we often want to plot the run time versus problem size to help us understand how the run time will scale to larger problem sizes.
"""

# ╔═╡ d07c4aac-616c-484c-8431-130d68869b00
begin
	estimate_pi(2)                    # make sure function is compiled
	n_list = map(i->2^i, 0:21)        # problem sizes to use for benchmarking
	estimate_pi_list = zeros(length(n_list))    # preallocate arrays to store results
	time_to_estimate_pi_list = zeros(length(n_list))
	for (i, n) in enumerate(n_list)
		time_to_estimate_pi_list[i] = @elapsed estimate_pi_list[i] = estimate_pi(n)
	end
end

# ╔═╡ 1ba1db1f-4e77-448c-bde0-82d4c0a39d31
let
	plt_performance = scatter(n_list,time_to_estimate_pi_list, 
		xscale=:log10, yscale=:log10,
		xlabel="Number of samples", ylabel="Run time (s)", legend=:none)
	plt_error = scatter(n_list, abs.(estimate_pi_list .- π), 
		xscale=:log10, yscale=:log10,
		#xlabel="Number of samples",
		ylabel="Error", legend=:none)
	plot(plt_error, plt_performance, layout=(2,1) )
end

# ╔═╡ 09b660ee-c075-4139-a34f-e3daaa34ca9e
md"""
As expected, as we use a larger number of samples we use to estimate π, the error in our estimate tends to decrease.  For small problem sizes (probably ~1-128), the runtime increases slower than linearly, because there are efficiencies that can be gained by grouping operations.  
Once the problem size gets big enough, the scaling is roughly linear over a large range of problem sizes.  
(Still, there can be bumps in the plot of run time versus the number of samples due to complications such as garbage collection being triggered in the middle of a calculation or the effects of caching behavior.)
"""

# ╔═╡ 1607eac9-e76f-4d1f-a9ce-981ce3be9bea
md"""
## Download a real-world file for benchmarking
Next, we're going to download a data file with the results of analyzing simulated Kepler light curves from the web.  This will be useful to show how sometimes "real world" data can behave differently than you might first guess. 

Julia has a built in `download` function that can be handy for this.  It relies on your system having some utilities already installed (e.g., `curl`, `wget` or `fetch`).  If you run this on a local system and run into trouble, then you can leave the cell below, and manually download the file to the data subdirectory.
"""

# ╔═╡ f27e1e8f-15eb-4754-a94c-7f37c54b871e
begin 
	url = "https://personal.psu.edu/~ebf11/data/kplr_dr25_inj1_plti.csv"
	path = "data"
	filename_csv = joinpath(path,basename(url)) # extract the filename and prepend "data/"
	if !isdir(path)  mkdir(path)  end          # make sure there's a data directory
	if true #!isfile(filename_csv)                   # skip downloading if file exists
	    time_to_download = @elapsed download(url,filename_csv)
	end
end

# ╔═╡ 80f02c3a-6751-48df-92ec-13f5c7d8c71e
if @isdefined time_to_download
	md"""
The starting input file is $(round(filesize(filename_csv)/1024^2,sigdigits=3)) MB.
Downloading it took $time_to_download seconds.

Note that this file was stored on a Penn State server.  The transfer might have even within a single data center.  If the download was coming from further away, then the time could have been significantly longer.
	"""
end

# ╔═╡ 624c9038-3008-4e78-a149-60796dacf9c0
md"""
Often, everything you needed for a lab is included in a GitHub repository.  So why did we download the file separately?  Two reasons.
1.  We'll compare how long it took to download the file to how long it takes to read the file.  Typically, downloading a file from the internet will be significantly slower than reading it from disk.  
2.  Notice the size of the file.  Git is great for tracking source code which tends to be modified in lots of incremental commits.  However, git wasn't designed for working with binary files that are likely to be updated.  It's particularly inefficient if you have large (or even sort-of-largish) binary files.  Since we're not going to be editing it, we'll simply download it once.  
"""

# ╔═╡ 047af20e-15af-46fa-af7f-954048324ee3
md"""
For comparison, we'll create a small test file of random values stored as `Float64`'s.  You can easily adjust the size of the small file used for benchmarking with random numbers by changing the values below.
"""

# ╔═╡ 7506f029-aa07-449f-bb8f-998a15d7d298
begin
	num_rows_small_df = 1024
	num_cols_small_df = 2
end

# ╔═╡ 4d633b2b-ec20-49cc-9571-5ff64dc306b0
if !(1<=num_rows_small_df)
	warning_box(md"Make sure to specify at least one row.")
elseif !(1<=num_cols_small_df<=1024)
	warning_box(md"Make sure to specify at least one column and no more than 1024.")
elseif num_rows_small_df*num_cols_small_df>1024^3
	warning_box(md"The values you chose would result in a >8GB file!")
end

# ╔═╡ 34dc2f22-fa58-414c-9376-7375cc8fdb71
begin
	small_df = DataFrame(
		("col_$i" for i in 1:num_cols_small_df)   # column names
		.=>
		(rand(num_rows_small_df) for i in 1:num_cols_small_df)  # values for each column
		)
	num_vals_small_df = prod(size(small_df))
end;

# ╔═╡ 191ba96e-2573-4bc1-a352-46a66e0a5c4f
md"""
# CSV files
Let's say that we'd like to read/write data as [CSV files](https://en.wikipedia.org/wiki/Comma-separated_values), so that it's easy for other programs to read in.  Using the CSV package, we can read a CSV file (or file with another delimiter) into a DataFrame (or several other tabular data structures) and write CSV files from a DataFrame with code like the following.
"""

# ╔═╡ 7c258a60-f74d-49d1-8a0f-cf04f47d1811
md"""
Is the run-time for the first time you write or read a CSV file much greater than the the second time?  That's likely because the first time a function is called (with a given set of argument types), Julia compiles a version of the function specific to those types.  
Click the button below to rerun the benchmarks.

$(@bind rerun_benchmarks Button("Rerun the benchmarks."))

The second time a function is called (with the same argument types), Julia can reuse the compiled function code to execute much faster.  This *Just-In-Time (JIT)* compilation is one of the key ingredients to Julia's high-computational throughput.  (It's also why there can be a noticeable latency the first time you call a function.)
Thus, the second run-time is much more representative of the actual cost to do the work.  This is the time that's relevant if you were planning to be reading/writing files so large or so often that the runtime becomes a concern.
"""

# ╔═╡ 82a757ad-566d-4c1d-8b3d-366ffd980fb4
begin
	rerun_benchmarks  # Trigger to rerun cell
	# Write a small test file 
	small_csv_filename = joinpath(path,"random_numbers.csv")
	time_to_write_csv_small_first = @elapsed CSV.write(small_csv_filename,small_df)
	time_to_read_csv_small_first = @elapsed small_df_from_csv_first = CSV.read(small_csv_filename,DataFrame) 
	# Write and read file a second time
	time_to_write_csv_small_second = @elapsed CSV.write(small_csv_filename,small_df)
	time_to_read_csv_small_second = @elapsed small_df_from_csv = CSV.read(small_csv_filename,DataFrame)
end;

# ╔═╡ 8722f1a5-ebbc-456f-bd5b-3735d8786373
md"""
**Benchmark results for small CSV file of random Float64 values**

|Operation | Time (s) | Floating point numbers | File size (bytes) |
|:---------|:---------|:----------------------:|------------------:|
| Write (first time)   | $(time_to_write_csv_small_first) | $(num_vals_small_df) | $(filesize(small_csv_filename)) 
| Write (second time)   | $(time_to_write_csv_small_second) | $(num_vals_small_df) | $(filesize(small_csv_filename)) 
| Read (first time) | $(time_to_read_csv_small_first) | $(num_vals_small_df) | $(filesize(small_csv_filename)) |
| Read (second time) | $(time_to_read_csv_small_second) | $(num_vals_small_df) | $(filesize(small_csv_filename)) |
"""

# ╔═╡ 76dfb5f5-2eeb-4fa9-9bb0-dfabe61f9c8d
md"""
**Q1a**:  Did reading or writing the file to disk take longer?   By what factor?
"""

# ╔═╡ 7bfffe60-cba0-41af-8487-b700f5c2d77f
response_1a = missing

# ╔═╡ ec40dba4-7217-4185-99f5-d821bdab036c
if ismissing(response_1a)   still_missing() end

# ╔═╡ 98e31c27-5401-4e28-93b9-a46660152a59
md"""
Next, we'll benchmark writing and reading CSV files with different numbers of rows.  
"""

# ╔═╡ da378686-45c6-40c3-99ad-2fb864dd6f73
n_rows_for_benchmarks = [2^1, 2^3, 2^5, 2^7, 2^9, 2^11, 2^13, 2^15, 2^17, 2^20];

# ╔═╡ 66b27cce-c654-4b18-b29f-8d86b9f5b2be
begin
	rerun_benchmarks
	time_to_write_csv_list = zeros(length(n_rows_for_benchmarks))
	time_to_read_csv_list = zeros(length(n_rows_for_benchmarks))
	time_to_read_csv2_list = zeros(length(n_rows_for_benchmarks))
	for (i, n) in enumerate(n_rows_for_benchmarks)
		tmp_csv_filename = joinpath(path,"random_numbers_$n.csv")
		tmp_df = DataFrame(a=rand(n),b=rand(n) ) 
		time_to_write_csv_list[i] = @elapsed CSV.write(tmp_csv_filename,tmp_df)
		time_to_read_csv_list[i] = @elapsed tmp_df = CSV.read(tmp_csv_filename,DataFrame) 
		time_to_read_csv2_list[i] = @elapsed tmp_df = CSV.read(tmp_csv_filename,DataFrame) 
	end
end

# ╔═╡ 29999a62-7a8a-4dd3-9201-fbec61aeb5de
let
	plt = plot(xscale=:log10, yscale=:log10,
		xlabel="Number of rows", ylabel="Run time (s)", 
		title="CSV File with $(num_cols_small_df) columns of Float64's", legend=:topleft)
	plot!(plt,n_rows_for_benchmarks,time_to_write_csv_list, marker=(:circle), label="Write")
	plot!(plt,n_rows_for_benchmarks,time_to_read_csv_list, marker=(:circle),  label="Read (first)")
	plot!(plt,n_rows_for_benchmarks,time_to_read_csv2_list, marker=(:circle), label="Read (second)")
end

# ╔═╡ 5df124c1-b4b4-4930-b1f4-25912bb807b0
md"""
Note that for small file sizes, the runtime is roughly flat.  
(It may even appear to get smaller to how the filesystem's caching behavior.)  
For larger files, the run-time eventually scales linearly with the number of values stored.  
"""

# ╔═╡ 69d5aa99-83d7-4cbc-8b2b-1175907aff34
protip(md"""
There can be little bumps and wiggles along the curve due to a variety of factors.
Some could be effects of caches and file block size (beyond scope of this class, but most interesting to computer scientists).
More likely, the wiggles you see are due to more mundane effects like what other users on the same compute node are doing, what other users accessing the same filesystem are doing, and what the operating system is doing at the time of your benchmarks.
If you wanted to perform more precise benchmarking, then you'd run the same tests hundreds or thousands of times to understand the typical and worst behavior.  
There is code to automate such tasks in [BenchmarkingTools.jl](https://github.com/JuliaCI/BenchmarkTools.jl).
""", "Curious about the wiggles?")

# ╔═╡ 5eaaf547-1244-4b6a-a3f1-e46092864305
md"""
**Q1b**:  The real-world datafile we downloaded near the top of the notebook has 146,294 rows and 25 columns of data.  
Based on the above results, how long do you predict it will take to read that CSV file?
"""

# ╔═╡ 507e1516-5433-49eb-831d-32426f30895e
response_1b = missing

# ╔═╡ eac67cc9-754b-4f7d-add8-93900a1b5b49
if ismissing(response_1b) still_missing() end

# ╔═╡ cc968c96-7f90-47d9-af7d-24b79556b5d6
if !(@isdefined already_benchmarked_csv_read)
	small_df_from_csv # force to wait until after benchmarking small files 
	time_to_read_csv = @elapsed df_csv = CSV.read(filename_csv, DataFrame, types=Dict(:TCE_ID=>String), missingstring="NA" )
	already_benchmarked_csv_read = true
end;

# ╔═╡ 02c91f91-8da8-49c9-bd81-00c0233b47b3
md"""
Note that in the cell above, we added some optional arguements to `CSV.read`.
By pasing `types`, we tell it what variable type to use for one column.  
(The `TCE_ID` is confusing because it's a string of numbers with a minus sign in the middle.)
We also passing `missingstring="NA"` so that Julia won't assign empty strings to be "missing.  This makes storage of the `TCE_ID`'s less efficient.  But it prevents problems later with the CFITSIO library that can't handle missing values.
There are many optional arguements to provide finer control like this.  See the function [documentation](https://csv.juliadata.org/stable/reading.html#CSV.read) for details.  
"""

# ╔═╡ 1fd95fea-2587-4d19-a1d4-aa6b3744a773
hint(md"It took $time_to_read_csv seconds to read the real-world CSV file.")

# ╔═╡ 945f5a55-3026-4497-9ece-8af878c87788
md"""
**Q1c:**  Once you've made your prediction in Q1b, mouse over the hint box to see how long it took in practice.  How did the time required to read the data in CSV format compare to your expectation?  If you were surprised, try to explain what may have caused the difference from your prediction.
"""

# ╔═╡ 57397ee4-9efc-48b3-b640-d2b7a10da633
response_1c = missing

# ╔═╡ 8059a6a3-384a-4344-8a23-650ee0be10c2
if ismissing(response_1c)  still_missing()   end

# ╔═╡ 64224c6b-c5a0-44f2-b2a0-7f77759cb848
md"""
Now, we'll try writing the same data out to a new CSV file.  
"""

# ╔═╡ f5b93929-2c59-4360-8c41-97a1324ba455
md"**Q1d:** How long do you predict it will take to write the same data to a new CSV file?  Once you've made your prediction, mouse over the hint box.  If you were surprised, try to explain what caused the difference from your prediction."

# ╔═╡ 122196fa-45ca-4031-85eb-4afd4782de9e
response_1d = missing

# ╔═╡ e9dc1456-616b-4e4b-b209-9f6ba4c48607
if ismissing(response_1d)  still_missing()   end

# ╔═╡ 3e550b71-4750-460b-be18-911a848a8f49
begin
	rerun_benchmarks
	small_df_from_csv
	filename_csv_out = replace(filename_csv, ".csv" => "_2.csv")  
	time_to_write_csv = @elapsed CSV.write(filename_csv_out, df_csv)
end;

# ╔═╡ f15d37a7-d962-4da0-977f-76729a3313be
hint(md"It took $time_to_write_csv seconds to write the CSV file.")

# ╔═╡ 28f195c4-4f61-4873-85d6-b4e3aaa3660f
md"""
# Binary formats: HDF5/JLD2

There are numerous binary file formats that one could use.  Here, we'll try using JLD2 which is a subset of the [HDF5](https://www.hdfgroup.org/solutions/hdf5/) file format.  This means that when [Julia's JLD2 package](https://github.com/JuliaIO/JLD2.jl) writes jld2 files, they can be read by other programs that can read HDF5 files.  However, a generic HDF5 file is not a valid JLD2 file.  If you want to read a HDF5 file, then you can use Julia's [HDF5.jl package](https://github.com/JuliaIO/HDF5.jl).  The [FileIO.jl](https://github.com/JuliaIO/FileIO.jl) package provides a common interface for reading and writing from multiple file formats, including these and several others.

As before, we'll call each function once using a small DataFrame, just so they get compiled before we benchmark them.
"""

# ╔═╡ 3837e439-250b-4577-b0d7-93352ec19f6e
begin
	rerun_benchmarks
	filename_jld2_small = replace(small_csv_filename, ".csv" => ".jld2")  
	 # Force compilation
	save(filename_jld2_small, Dict("small_df" => small_df) )
	small_df_from_jld2 = load(filename_jld2_small, "small_df")
	# Write data file
	time_to_write_jld2_small = @elapsed save(filename_jld2_small, Dict("small_df" => small_df) ) 
	# Read data file
	time_to_read_jld2_small_first = @elapsed small_df_from_jld2 = load(filename_jld2_small, "small_df")
	time_to_read_jld2_small_second = @elapsed small_df_from_jld2 = load(filename_jld2_small, "small_df")
end;

# ╔═╡ 6c147ad6-95b4-4008-bd9b-72f1ece8de5c
md"""
Any floating point value stored as a `Float64` (commonly referred to as "double precision") uses exactly 8 bytes (8 bits/byte, so 64 bits total).  
In general, a floating point value stored as a `Float64` (commonly referred to as "double precision") requires 17 characters to guarantee that when it is read back it will take on the exact same numerical value.  

**Q2a:** Predict how the filesize of the JLD2 files will compare to the filesize of the small CSV files.
"""

# ╔═╡ 9b411269-f1bc-4e1b-93c8-78f5407597cb
response_2a = missing

# ╔═╡ 7cda896c-59e4-4c08-8237-7869589604ba
if ismissing(response_2a)  still_missing()   end

# ╔═╡ afd68362-8459-4994-bdc7-1338640a4543
md"""
**Q2b:** Predict how the time required to read the small JLD2 file will compare to the time required to read the small CSV file.
"""

# ╔═╡ 28af4229-5de4-47ef-9fc8-4033901c50b8
response_2b = missing

# ╔═╡ 8bfde242-e2ec-4556-8b54-bbafbe1b1ddc
if ismissing(response_2b)  still_missing()   end

# ╔═╡ ced8a0e5-b6e7-4a72-a296-d0ae3865a6ee
md"""
Once you enter your responses above, you should see a table of times and file sizes appear.
"""

# ╔═╡ 86728419-ebb4-4d90-88bb-346c763e0fb9
if !ismissing(response_2a) && !ismissing(response_2b)  
md"""
**Results for CSV vs JLD2 (small file of random values)**

|Operation | Time (s) | Floating point numbers | File size (bytes) |
|:---------|:---------|:----------------------:|------------------:|
| **CSV**      | | | |
| Write    | $(time_to_write_csv_small_second) | $(num_vals_small_df) | $(filesize(small_csv_filename)) 
| Read (first time) | $(time_to_read_csv_small_first) | $(num_vals_small_df) | $(filesize(small_csv_filename)) |
| Read (second time) | $(time_to_read_csv_small_second) | $(num_vals_small_df) | $(filesize(small_csv_filename)) |
| **HDF5/JLD2**      |   |   |   |
| Write    | $(time_to_write_jld2_small) | $(num_vals_small_df) | $(filesize(filename_jld2_small)) 
| Read (first time) | $(time_to_read_jld2_small_first) | $(num_vals_small_df) | $(filesize(filename_jld2_small)) |
| Read (second time) | $(time_to_read_jld2_small_second) | $(num_vals_small_df) | $(filesize(filename_jld2_small)) |
"""	
end

# ╔═╡ b8a2c1a0-381e-47e0-acc5-65ccd905d519
md"""
**Q2c:** How do your predictions compare to the actual results?  
Try to explain any significant differences.

"""

# ╔═╡ ca62f6ad-1dd5-4ca5-a957-d82e38198b11
response_2c = missing

# ╔═╡ 5a2b064c-21f3-4ce6-a3e5-ab0a9f98dd5c
if ismissing(response_2c)  still_missing()   end

# ╔═╡ 570fd826-23fd-46ee-bdb4-58fb0c45719a
md"""
Now, we'll test how long it takes to save and load the data from our large CSV file into/from a JLD2 file.
"""

# ╔═╡ 691410bb-0472-4800-a90d-29ddf947de3e
begin
	rerun_benchmarks
	small_df_from_jld2  # Force to wait until after benchmarking small file
	filename_jld2 = replace(filename_csv, ".csv" => ".jld2") 
	# Write data to HDF5/JLD2 file
	time_to_write_jld2 = @elapsed save(filename_jld2, Dict("data" => df_csv) ) 
	# Read data back from HDF5/JLD2 file
	time_to_read_jld2_first = @elapsed df_from_jld2 = load(filename_jld2, "data")
	time_to_read_jld2_second = @elapsed df_from_jld2 = load(filename_jld2, "data")
end;

# ╔═╡ 6143bcd4-32b7-48c3-8b88-4b615d20f1b3
md"""
**Q2d:** Predict how the filesize of the JLD2 file with the large dataset we downloaded will compare to the filesize of the original CSV file we downloaded.
"""

# ╔═╡ 55eaadf5-d352-4673-a56c-effb952093dc
response_2d = missing

# ╔═╡ 107a432d-39e8-4db2-9820-a57a88589d6e
if ismissing(response_2d)  still_missing()   end

# ╔═╡ 56124135-23ff-49cd-8a84-c22f178533c6
md"""
**Q2e:** Predict how the time required to read the JLD2 file containing the large dataset we downloaded will compare to the time required to read the original CSV file.
"""

# ╔═╡ 8856674a-6b72-4dfa-9753-0dcd9e578068
response_2e = missing

# ╔═╡ 4c17241a-1f1a-4a49-8a13-2deb0e266ce6
if ismissing(response_2e)  still_missing()   end

# ╔═╡ 6a35e827-d987-4136-b33f-1c7a403e1ce4
md"""
Once you enter your responses above, you should see a table of times and file sizes appear.
"""

# ╔═╡ ad72b21c-f5ec-4dab-8ccf-d544eb006ec1
if !ismissing(response_2d) && !ismissing(response_2e)  
md"""
**Results for CSV vs JLD2 (large file)**

|Operation | Time (s) |  File size (bytes) |
|:---------|:---------|-------------------:|
| **CSV**      | | | |
| Write    | $(time_to_write_csv) | $(filesize(filename_csv)) 
| Read (first time) | $(time_to_read_csv) | $(filesize(filename_csv)) |
| Read (second time) | $(time_to_read_csv) | $(filesize(filename_csv)) |
| **HDF5/JLD2**      |   |   |   |
| Write    | $(time_to_write_jld2) | $(filesize(filename_jld2)) 
| Read (first time) | $(time_to_read_jld2_first) |  $(filesize(filename_jld2)) |
| Read (second time) | $(time_to_read_jld2_second) | $(filesize(filename_jld2)) |
"""	
end

# ╔═╡ e6c93876-e832-4f28-9777-b9602d5204f9
md"""
There's a good chance that your predictions may have been overly optimistic about the filesize and read time of the JLD2 files.  In order to understand what cause that, inspect the first few rows of the dataframe being stored.
"""

# ╔═╡ 9e10abc3-7722-4d7d-b2d1-9baf6eea94ba
df_csv

# ╔═╡ 1de771de-f32b-4f32-8dbe-c56295fd935d
md"""
**Q2f:** With the benefit of hindsight, why did the file take less byte when stored in CSV format than JLD2?  
"""

# ╔═╡ b800d43d-e688-4059-8aa2-0fddb45e2940
response_2f = missing

# ╔═╡ 0eb83f4b-64cc-4864-8a80-9305da59e82f
if ismissing(response_2f)  still_missing()   end

# ╔═╡ 7a17bf14-b749-4136-bfde-e5599a8738be
md"""
**Q2g:** What changes could be made that would allow JLD2 to store the data more in less space than CSV?  
"""

# ╔═╡ ec00c9a5-2140-4b34-bab4-9a89e09eecdc
response_2g = missing

# ╔═╡ bf2f48b7-fde9-41df-83e8-26ee557b6f1c
if ismissing(response_2g)  still_missing()   end

# ╔═╡ 8cbb1c90-bd94-44b5-80b6-81d38f3e6252
md"**Q2h.**  How long do you think it will take to load the data from the JLD2 file? "

# ╔═╡ c3065acf-6205-455f-ba74-ca51f3f6761b
response_2h = missing

# ╔═╡ fc01d57f-c90b-4231-96be-ddd48656d55e
md"""
# Flexible Format: FITS

Astronomers often use the [FITS file format](https://en.wikipedia.org/wiki/FITS).  Like [HDF
5](https://www.hdfgroup.org/solutions/hdf5/), it's a very flexible (e.g., it can store both text and binary data) and thus complicated file
 format.  
Therefore, nearly all FITS users call a common [FITSIO library written in C](https://heasarc.gsfc.nasa.gov/fitsio/), rather than implementing code themselves.  Indeed, that's what [Julia's FITSIO.jl package](https://github.com/JuliaAstro/FITSIO.jl) does.

Unfortunately, the FITSIO package isn't as polished as the others.  It expects a `Dict` rather than a `DataFrame`, and it can't handle missing values.  So I've provided some helper functions at the bottom of the notebook.  Also, FITS files have complicated headers, so I'll provide a function to read all the tabular data from a simple FITS file.  As usual, we'll use each function once, so that Julia compiles them before we start timing.
"""

# ╔═╡ 5cadfa6c-1e6b-4450-ba4a-4a43a6a31fa7
md"""
**Q3a:** Based on the results above for CSV and HDF5/JLD2 formats, predict how large the FITS file to store our small file of random values will be.
"""

# ╔═╡ c7373630-aab0-45a3-b9b9-5ccbe8785ff1
response_3a = missing

# ╔═╡ 98bac9c4-28e4-46aa-ab82-4c5017bbdfa4
if ismissing(response_3a)  still_missing()   end

# ╔═╡ 91957d9b-ce75-4249-b125-e312c0a2a454
md"""
**Q3b:** Based on the results above for CSV and HDF5/JLD2 formats, predict the runtimes for reading/writing the small FITS file of with random values.
"""

# ╔═╡ cdacd651-19af-41d5-a5c0-75ffab32300c
response_3b = missing

# ╔═╡ 7c4c83de-48b4-474d-9995-ea86ed06af6d
if ismissing(response_3b)  still_missing()   end

# ╔═╡ b9e16183-4eb5-468d-9486-7a3b6571777c
md"""
**Q3c:** How did you predictions compare to the actual results?
"""

# ╔═╡ a63af23d-5408-4815-b898-1ab62670d37a
response_3c = missing

# ╔═╡ 4960aac7-29e3-415b-bbd0-2ecdca26fd46
if ismissing(response_3c)  still_missing()   end

# ╔═╡ 1f39b2d0-7825-4e6f-abc1-028b4d59b377
protip(md"""
The JLD2 format includes more extra metadata (e.g., information about the variable type for each column of the dataframe), explaining the slightly larger file size.  However, this difference is so small that it will have a negligible impact on the runtimes.  This is extremely convenient since it allows you to read and write a DataFrame (or any other Julia data type) without having to write special functions to store each type. 

I'm not entirely sure why the runtime for reading/writing a small JLD2 file of floats is significantly greater than for FITS files.   I'm guessing some combination of the FITS format being tuned for common variable types and the CFITSIO library being more mature and better optimized than the JLD2 code.
""","Why did FITS outperform HDF5/JLD2?")

# ╔═╡ c272215b-6d9a-4be5-ab7b-bb17319cd294
md"""
**Q3d:** Based on the results above, predict how the file size and runtime to read/write the large real world data files using the FITS format.   
"""

# ╔═╡ d5e4f29d-ee33-4fac-afd8-2d6e69f611ac
response_3d = missing

# ╔═╡ 3314b839-293c-4731-95b5-61b9b25613db
if ismissing(response_3d)  still_missing()   end

# ╔═╡ 3b232365-f2fe-4edb-a39f-3e37c8cbb666
md"Now we can time how long it takes to write and read the real-world data as FITS files."

# ╔═╡ 6046dff3-8725-4252-8516-2cd0dfc14f6f
md"""
**Q3e:** How did your predictions compare to the actual results?  
"""

# ╔═╡ d69bc955-6119-4327-bfd4-ca4723bbaac1
response_3e = missing

# ╔═╡ e00bdaa1-fa0a-404d-9da2-595c416a2097
if ismissing(response_3e)  still_missing()   end

# ╔═╡ bf659991-1ed2-4bef-81ef-9f04bd3620f8
protip(md"""
I'm not entirely sure why the runtime for reading the real-world FITS files the second is significantly greater than for HDF5/JLD2 files.   I'm guessing it's that some combination of file system caching behavior and HDF5 and JLD2 being better optimized for working with strings.
""","Why did HDF5/JLD2 outperform FITS?")

# ╔═╡ 8def87d2-f10b-4a82-b353-a6477eeead9b
md"## Implications for your project"

# ╔═╡ c74b3105-f480-4688-b85f-3e7dff70da3b
md"""
**Q4a:**  How does the time required to read data from the large file we downloaded near the top of the notebook compare to the time required to download the files from the internet ($time_to_download seconds)?  
"""

# ╔═╡ 55438c09-1d94-4ff7-90c3-0cc6064a091e
response_4a = missing

# ╔═╡ 1004feae-cf1a-4ecf-b443-34f5da22f4ec
if ismissing(response_4a)  still_missing()   end

# ╔═╡ 2ffd6e61-2fd2-4f91-9ebb-9b67183803b6
md"""
**Q4b:**  
Will your project need to download significant size files from the internet?

If so, very roughly how large do you expect they will be?  
How long do you expect it to take to download or read those files?

Would it make sense for you to preprocess your data and write it into a different file format than it is originally stored in, so as to make the dashboard more responsive?  
"""

# ╔═╡ bcc796c9-db11-4a09-a5f9-215127ac0938
response_4b = missing

# ╔═╡ 7790b2e0-36a3-44c5-aa69-83a146ca7799
if ismissing(response_4b)   still_missing()   end

# ╔═╡ 29415ddc-e002-4f56-a169-95f7b1c36be9
md"# Helper Functions"

# ╔═╡ fb23d6c6-b812-4fe1-b224-0014bedbd43f
ChooseDisplayMode()

# ╔═╡ 14cca8ce-cc61-4fae-b871-21c3fd23d0ea
"Convert a DataFrame to a OrderedDict"
function convert_dataframe_to_dict(df::DataFrame)
	d = OrderedDict(zip(names(df),collect.(eachcol(df))))
end

# ╔═╡ 28fc8de4-749b-4093-b32f-c398f8d27d3d
"Write a DataFrame to a FITS file."
function write_dataframe_as_fits(filename::String, df::DataFrame)
    try 
       dict = convert_dataframe_to_dict(df) 
       fits_file = FITS(filename,"w")
       write(fits_file, dict )
       close(fits_file)
    catch
        @warn("There was a problem writing a dataframe to " * filename * ".")
    end
end


# ╔═╡ 57b422e5-0ad0-4674-bdd3-a8358bc7aaeb

"""
   `read_fits_table( filename; [hdu] )`

Read the columns of the table in the specified header data unit (hdu) from a FITS file.
If all tables are the same size, then they are returned in a DataFrame.
Otherwise, they are returned as a Dict.
Defaults to reading from hdu = 2
"""
function read_fits_tables(filename::String; hdu::Integer=2)
	dict = OrderedDict{String,Any}()
    fits_file = FITS(filename,"r")
    @assert 1 <= hdu <= length(fits_file) 
    header = read_header(fits_file[hdu])
    for i in 1:length(header)
        c::String = get_comment(header,i)
        if !occursin("label for field",c)
            continue
        end
        h::String = header[i]
        #@assert typeof(h) == String
        try  
            dict[h] = read(fits_file[2],h)
        catch
            @warn "# Problem reading table column " * h * "."
        end
    end
    close(fits_file)
	# If all table same size, then put into a DataFrame
	if length(unique(size.(values(dict)))) == 1
    	result = DataFrame(dict, copycols=false)
	else  # Otherwise return data in dict
		result = dict
	end
	return result 
end


# ╔═╡ e05f16d6-eb50-49a9-bf14-95d63c9da7ff
begin
	rerun_benchmarks
	filename_fits_small = replace(small_csv_filename, ".csv" => ".fits")  
	# Force compilation
	write_dataframe_as_fits(filename_fits_small,small_df) 
	small_df_fits = read_fits_tables(filename_fits_small)
	# Write data to FITS file
	time_to_write_fits_small = @elapsed write_dataframe_as_fits(filename_fits_small,small_df)
	# Read data back from FITS file
	time_to_read_fits_small_first = @elapsed small_df_fits = read_fits_tables(filename_fits_small)
	time_to_read_fits_small_second = @elapsed small_df_fits = read_fits_tables(filename_fits_small)
end;

# ╔═╡ 9e3e9fe8-7ab9-4b90-8596-f225a44d73c4
if !ismissing(response_3a) && !ismissing(response_3b)  
md"""
**Results for CSV vs JLD2 vs FITS (small file of random values)**

|Operation | Time (s) | Floating point numbers | File size (bytes) |
|:---------|:---------|:----------------------:|------------------:|
| **CSV**      | | | |
| Write    | $(time_to_write_csv_small_second) | $(num_vals_small_df) | $(filesize(small_csv_filename)) 
| Read (first time) | $(time_to_read_csv_small_first) | $(num_vals_small_df) | $(filesize(small_csv_filename)) |
| Read (second time) | $(time_to_read_csv_small_second) | $(num_vals_small_df) | $(filesize(small_csv_filename)) |
| **HDF5/JLD2**      |   |   |   |
| Write    | $(time_to_write_jld2_small) | $(num_vals_small_df) | $(filesize(filename_jld2_small)) 
| Read (first time) | $(time_to_read_jld2_small_first) | $(num_vals_small_df) | $(filesize(filename_jld2_small)) |
| Read (second time) | $(time_to_read_jld2_small_second) | $(num_vals_small_df) | $(filesize(filename_jld2_small)) |
| **FITS**      |   |   |   |
| Write    | $(time_to_write_fits_small) | $(num_vals_small_df) | $(filesize(filename_fits_small)) 
| Read (first time) | $(time_to_read_fits_small_first) | $(num_vals_small_df) | $(filesize(filename_fits_small)) |
| Read (second time) | $(time_to_read_fits_small_second) | $(num_vals_small_df) | $(filesize(filename_fits_small)) |
"""	
end

# ╔═╡ 1992595f-9976-4b18-bf9c-df8a73d30dc8
begin
	rerun_benchmarks    # trigger if ask to rerun benchmarks
	small_df_fits  # Force to wait until after benchmarking small file
	filename_fits = replace(filename_csv, ".csv" => ".fits") 
	time_to_write_fits = @elapsed write_dataframe_as_fits(filename_fits,df_csv)
	time_to_read_fits_first = @elapsed df_from_fits = read_fits_tables(filename_fits)
	time_to_read_fits_second = @elapsed df_from_fits = read_fits_tables(filename_fits)
end;

# ╔═╡ ed7fe6ad-bc74-42b8-8348-613541afcacf
if !ismissing(response_3d)  
md"""
**Results for CSV vs JLD2 vs FITS (large file)**

|Operation | Time (s) |  File size (bytes) |
|:---------|:---------|-------------------:|
| **CSV**      | | | |
| Write    | $(time_to_write_csv) | $(filesize(filename_csv)) 
| Read (first time) | $(time_to_read_csv) | $(filesize(filename_csv)) |
| Read (second time) | $(time_to_read_csv) | $(filesize(filename_csv)) |
| **HDF5/JLD2**      |   |   |   |
| Write    | $(time_to_write_jld2) | $(filesize(filename_jld2)) 
| Read (first time) | $(time_to_read_jld2_first) |  $(filesize(filename_jld2)) |
| Read (second time) | $(time_to_read_jld2_second) | $(filesize(filename_jld2)) |
| **FITS**      |   |   |   |
| Write    | $(time_to_write_fits) | $(filesize(filename_fits)) 
| Read (first time) | $(time_to_read_fits_first) |  $(filesize(filename_fits)) |
| Read (second time) | $(time_to_read_fits_second) | $(filesize(filename_fits)) |
"""	
end

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
CSV = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
FITSIO = "525bcba6-941b-5504-bd06-fd0dc1a4d2eb"
FileIO = "5789e2e9-d7fb-5bc7-8068-2c6fae9b9549"
InlineStrings = "842dd82b-1e85-43dc-bf29-5d0ee9dffc48"
JLD2 = "033835bb-8acc-5ee8-8aae-3f567f8a3819"
OrderedCollections = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
Plots = "91a5bcdd-55d7-5caf-9e0b-520d859cae80"
PlutoTeachingTools = "661c6b06-c737-4d37-b85c-46df65de6f69"
PlutoUI = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.7.3"
manifest_format = "2.0"

[[deps.AbstractPlutoDingetjes]]
deps = ["Pkg"]
git-tree-sha1 = "8eaf9f1b4921132a4cff3f36a1d9ba923b14a481"
uuid = "6e696c72-6542-2067-7265-42206c756150"
version = "1.1.4"

[[deps.ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"

[[deps.Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"

[[deps.Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"

[[deps.BitFlags]]
git-tree-sha1 = "84259bb6172806304b9101094a7cc4bc6f56dbc6"
uuid = "d1d4a3ce-64b1-5f1a-9ba4-7e7e69966f35"
version = "0.1.5"

[[deps.Bzip2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "19a35467a82e236ff51bc17a3a44b69ef35185a2"
uuid = "6e34b625-4abd-537c-b88f-471c36dfa7a0"
version = "1.0.8+0"

[[deps.CFITSIO]]
deps = ["CFITSIO_jll"]
git-tree-sha1 = "8425c47db102577eefb93cb37b4480e750116b0d"
uuid = "3b1b4be9-1499-4b22-8d78-7db3344d1961"
version = "1.4.1"

[[deps.CFITSIO_jll]]
deps = ["Artifacts", "JLLWrappers", "LibCURL_jll", "Libdl", "Pkg", "Zlib_jll"]
git-tree-sha1 = "9c91a9358de42043c3101e3a29e60883345b0b39"
uuid = "b3e40c51-02ae-5482-8a39-3ace5868dcf4"
version = "4.0.0+0"

[[deps.CSV]]
deps = ["CodecZlib", "Dates", "FilePathsBase", "InlineStrings", "Mmap", "Parsers", "PooledArrays", "SentinelArrays", "Tables", "Unicode", "WeakRefStrings"]
git-tree-sha1 = "873fb188a4b9d76549b81465b1f75c82aaf59238"
uuid = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
version = "0.10.4"

[[deps.Cairo_jll]]
deps = ["Artifacts", "Bzip2_jll", "Fontconfig_jll", "FreeType2_jll", "Glib_jll", "JLLWrappers", "LZO_jll", "Libdl", "Pixman_jll", "Pkg", "Xorg_libXext_jll", "Xorg_libXrender_jll", "Zlib_jll", "libpng_jll"]
git-tree-sha1 = "4b859a208b2397a7a623a03449e4636bdb17bcf2"
uuid = "83423d85-b0ee-5818-9007-b63ccbeb887a"
version = "1.16.1+1"

[[deps.ChainRulesCore]]
deps = ["Compat", "LinearAlgebra", "SparseArrays"]
git-tree-sha1 = "e7ff6cadf743c098e08fca25c91103ee4303c9bb"
uuid = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
version = "1.15.6"

[[deps.ChangesOfVariables]]
deps = ["ChainRulesCore", "LinearAlgebra", "Test"]
git-tree-sha1 = "38f7a08f19d8810338d4f5085211c7dfa5d5bdd8"
uuid = "9e997f8a-9a97-42d5-a9f1-ce6bfc15e2c0"
version = "0.1.4"

[[deps.CodeTracking]]
deps = ["InteractiveUtils", "UUIDs"]
git-tree-sha1 = "1833bda4a027f4b2a1c984baddcf755d77266818"
uuid = "da1fd8a2-8d9e-5ec2-8556-3022fb5608a2"
version = "1.1.0"

[[deps.CodecZlib]]
deps = ["TranscodingStreams", "Zlib_jll"]
git-tree-sha1 = "ded953804d019afa9a3f98981d99b33e3db7b6da"
uuid = "944b1d66-785c-5afd-91f1-9de20f533193"
version = "0.7.0"

[[deps.ColorSchemes]]
deps = ["ColorTypes", "ColorVectorSpace", "Colors", "FixedPointNumbers", "Random"]
git-tree-sha1 = "1fd869cc3875b57347f7027521f561cf46d1fcd8"
uuid = "35d6a980-a343-548e-a6ea-1d62b119f2f4"
version = "3.19.0"

[[deps.ColorTypes]]
deps = ["FixedPointNumbers", "Random"]
git-tree-sha1 = "eb7f0f8307f71fac7c606984ea5fb2817275d6e4"
uuid = "3da002f7-5984-5a60-b8a6-cbb66c0b333f"
version = "0.11.4"

[[deps.ColorVectorSpace]]
deps = ["ColorTypes", "FixedPointNumbers", "LinearAlgebra", "SpecialFunctions", "Statistics", "TensorCore"]
git-tree-sha1 = "d08c20eef1f2cbc6e60fd3612ac4340b89fea322"
uuid = "c3611d14-8923-5661-9e6a-0046d554d3a4"
version = "0.9.9"

[[deps.Colors]]
deps = ["ColorTypes", "FixedPointNumbers", "Reexport"]
git-tree-sha1 = "417b0ed7b8b838aa6ca0a87aadf1bb9eb111ce40"
uuid = "5ae59095-9a9b-59fe-a467-6f913c188581"
version = "0.12.8"

[[deps.Compat]]
deps = ["Dates", "LinearAlgebra", "UUIDs"]
git-tree-sha1 = "5856d3031cdb1f3b2b6340dfdc66b6d9a149a374"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "4.2.0"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"

[[deps.Contour]]
git-tree-sha1 = "d05d9e7b7aedff4e5b51a029dced05cfb6125781"
uuid = "d38c429a-6771-53c6-b99e-75d170b6e991"
version = "0.6.2"

[[deps.Crayons]]
git-tree-sha1 = "249fe38abf76d48563e2f4556bebd215aa317e15"
uuid = "a8cc5b0e-0ffa-5ad4-8c14-923d3ee1735f"
version = "4.1.1"

[[deps.DataAPI]]
git-tree-sha1 = "46d2680e618f8abd007bce0c3026cb0c4a8f2032"
uuid = "9a962f9c-6df0-11e9-0e5d-c546b8b5ee8a"
version = "1.12.0"

[[deps.DataFrames]]
deps = ["Compat", "DataAPI", "Future", "InvertedIndices", "IteratorInterfaceExtensions", "LinearAlgebra", "Markdown", "Missings", "PooledArrays", "PrettyTables", "Printf", "REPL", "Reexport", "SortingAlgorithms", "Statistics", "TableTraits", "Tables", "Unicode"]
git-tree-sha1 = "db2a9cb664fcea7836da4b414c3278d71dd602d2"
uuid = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
version = "1.3.6"

[[deps.DataStructures]]
deps = ["Compat", "InteractiveUtils", "OrderedCollections"]
git-tree-sha1 = "d1fff3a548102f48987a52a2e0d114fa97d730f0"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.18.13"

[[deps.DataValueInterfaces]]
git-tree-sha1 = "bfc1187b79289637fa0ef6d4436ebdfe6905cbd6"
uuid = "e2d170a0-9d28-54be-80f0-106bbe20a464"
version = "1.0.0"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"

[[deps.DelimitedFiles]]
deps = ["Mmap"]
uuid = "8bb1440f-4735-579b-a4ab-409b98df4dab"

[[deps.Distributed]]
deps = ["Random", "Serialization", "Sockets"]
uuid = "8ba89e20-285c-5b6f-9357-94700520ee1b"

[[deps.DocStringExtensions]]
deps = ["LibGit2"]
git-tree-sha1 = "5158c2b41018c5f7eb1470d558127ac274eca0c9"
uuid = "ffbed154-4ef7-542d-bbb7-c09d3a79fcae"
version = "0.9.1"

[[deps.Downloads]]
deps = ["ArgTools", "FileWatching", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"

[[deps.Expat_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "bad72f730e9e91c08d9427d5e8db95478a3c323d"
uuid = "2e619515-83b5-522b-bb60-26c02a35a201"
version = "2.4.8+0"

[[deps.FFMPEG]]
deps = ["FFMPEG_jll"]
git-tree-sha1 = "b57e3acbe22f8484b4b5ff66a7499717fe1a9cc8"
uuid = "c87230d0-a227-11e9-1b43-d7ebe4e7570a"
version = "0.4.1"

[[deps.FFMPEG_jll]]
deps = ["Artifacts", "Bzip2_jll", "FreeType2_jll", "FriBidi_jll", "JLLWrappers", "LAME_jll", "Libdl", "Ogg_jll", "OpenSSL_jll", "Opus_jll", "PCRE2_jll", "Pkg", "Zlib_jll", "libaom_jll", "libass_jll", "libfdk_aac_jll", "libvorbis_jll", "x264_jll", "x265_jll"]
git-tree-sha1 = "74faea50c1d007c85837327f6775bea60b5492dd"
uuid = "b22a6f82-2f65-5046-a5b2-351ab43fb4e5"
version = "4.4.2+2"

[[deps.FITSIO]]
deps = ["CFITSIO", "Printf", "Reexport", "Tables"]
git-tree-sha1 = "3b342f0c3bb37371e1e2ad37672a9c960f9abcb6"
uuid = "525bcba6-941b-5504-bd06-fd0dc1a4d2eb"
version = "0.17.0"

[[deps.FileIO]]
deps = ["Pkg", "Requires", "UUIDs"]
git-tree-sha1 = "94f5101b96d2d968ace56f7f2db19d0a5f592e28"
uuid = "5789e2e9-d7fb-5bc7-8068-2c6fae9b9549"
version = "1.15.0"

[[deps.FilePathsBase]]
deps = ["Compat", "Dates", "Mmap", "Printf", "Test", "UUIDs"]
git-tree-sha1 = "e27c4ebe80e8699540f2d6c805cc12203b614f12"
uuid = "48062228-2e41-5def-b9a4-89aafe57970f"
version = "0.9.20"

[[deps.FileWatching]]
uuid = "7b1f6079-737a-58dc-b8bc-7a2ca5c1b5ee"

[[deps.FixedPointNumbers]]
deps = ["Statistics"]
git-tree-sha1 = "335bfdceacc84c5cdf16aadc768aa5ddfc5383cc"
uuid = "53c48c17-4a7d-5ca2-90c5-79b7896eea93"
version = "0.8.4"

[[deps.Fontconfig_jll]]
deps = ["Artifacts", "Bzip2_jll", "Expat_jll", "FreeType2_jll", "JLLWrappers", "Libdl", "Libuuid_jll", "Pkg", "Zlib_jll"]
git-tree-sha1 = "21efd19106a55620a188615da6d3d06cd7f6ee03"
uuid = "a3f928ae-7b40-5064-980b-68af3947d34b"
version = "2.13.93+0"

[[deps.Formatting]]
deps = ["Printf"]
git-tree-sha1 = "8339d61043228fdd3eb658d86c926cb282ae72a8"
uuid = "59287772-0a20-5a39-b81b-1366585eb4c0"
version = "0.4.2"

[[deps.FreeType2_jll]]
deps = ["Artifacts", "Bzip2_jll", "JLLWrappers", "Libdl", "Pkg", "Zlib_jll"]
git-tree-sha1 = "87eb71354d8ec1a96d4a7636bd57a7347dde3ef9"
uuid = "d7e528f0-a631-5988-bf34-fe36492bcfd7"
version = "2.10.4+0"

[[deps.FriBidi_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "aa31987c2ba8704e23c6c8ba8a4f769d5d7e4f91"
uuid = "559328eb-81f9-559d-9380-de523a88c83c"
version = "1.0.10+0"

[[deps.Future]]
deps = ["Random"]
uuid = "9fa8497b-333b-5362-9e8d-4d0656e87820"

[[deps.GLFW_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libglvnd_jll", "Pkg", "Xorg_libXcursor_jll", "Xorg_libXi_jll", "Xorg_libXinerama_jll", "Xorg_libXrandr_jll"]
git-tree-sha1 = "d972031d28c8c8d9d7b41a536ad7bb0c2579caca"
uuid = "0656b61e-2033-5cc2-a64a-77c0f6c09b89"
version = "3.3.8+0"

[[deps.GR]]
deps = ["Base64", "DelimitedFiles", "GR_jll", "HTTP", "JSON", "Libdl", "LinearAlgebra", "Pkg", "Preferences", "Printf", "Random", "Serialization", "Sockets", "Test", "UUIDs"]
git-tree-sha1 = "a9ec6a35bc5ddc3aeb8938f800dc599e652d0029"
uuid = "28b8d3ca-fb5f-59d9-8090-bfdbd6d07a71"
version = "0.69.3"

[[deps.GR_jll]]
deps = ["Artifacts", "Bzip2_jll", "Cairo_jll", "FFMPEG_jll", "Fontconfig_jll", "GLFW_jll", "JLLWrappers", "JpegTurbo_jll", "Libdl", "Libtiff_jll", "Pixman_jll", "Pkg", "Qt5Base_jll", "Zlib_jll", "libpng_jll"]
git-tree-sha1 = "bc9f7725571ddb4ab2c4bc74fa397c1c5ad08943"
uuid = "d2c73de3-f751-5644-a686-071e5b155ba9"
version = "0.69.1+0"

[[deps.Gettext_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Libiconv_jll", "Pkg", "XML2_jll"]
git-tree-sha1 = "9b02998aba7bf074d14de89f9d37ca24a1a0b046"
uuid = "78b55507-aeef-58d4-861c-77aaff3498b1"
version = "0.21.0+0"

[[deps.Glib_jll]]
deps = ["Artifacts", "Gettext_jll", "JLLWrappers", "Libdl", "Libffi_jll", "Libiconv_jll", "Libmount_jll", "PCRE2_jll", "Pkg", "Zlib_jll"]
git-tree-sha1 = "fb83fbe02fe57f2c068013aa94bcdf6760d3a7a7"
uuid = "7746bdde-850d-59dc-9ae8-88ece973131d"
version = "2.74.0+1"

[[deps.Graphite2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "344bf40dcab1073aca04aa0df4fb092f920e4011"
uuid = "3b182d85-2403-5c21-9c21-1e1f0cc25472"
version = "1.3.14+0"

[[deps.Grisu]]
git-tree-sha1 = "53bb909d1151e57e2484c3d1b53e19552b887fb2"
uuid = "42e2da0e-8278-4e71-bc24-59509adca0fe"
version = "1.0.2"

[[deps.HTTP]]
deps = ["Base64", "CodecZlib", "Dates", "IniFile", "Logging", "LoggingExtras", "MbedTLS", "NetworkOptions", "OpenSSL", "Random", "SimpleBufferStream", "Sockets", "URIs", "UUIDs"]
git-tree-sha1 = "4abede886fcba15cd5fd041fef776b230d004cee"
uuid = "cd3eb016-35fb-5094-929b-558a96fad6f3"
version = "1.4.0"

[[deps.HarfBuzz_jll]]
deps = ["Artifacts", "Cairo_jll", "Fontconfig_jll", "FreeType2_jll", "Glib_jll", "Graphite2_jll", "JLLWrappers", "Libdl", "Libffi_jll", "Pkg"]
git-tree-sha1 = "129acf094d168394e80ee1dc4bc06ec835e510a3"
uuid = "2e76f6c2-a576-52d4-95c1-20adfe4de566"
version = "2.8.1+1"

[[deps.Hyperscript]]
deps = ["Test"]
git-tree-sha1 = "8d511d5b81240fc8e6802386302675bdf47737b9"
uuid = "47d2ed2b-36de-50cf-bf87-49c2cf4b8b91"
version = "0.0.4"

[[deps.HypertextLiteral]]
deps = ["Tricks"]
git-tree-sha1 = "c47c5fa4c5308f27ccaac35504858d8914e102f9"
uuid = "ac1192a8-f4b3-4bfe-ba22-af5b92cd3ab2"
version = "0.9.4"

[[deps.IOCapture]]
deps = ["Logging", "Random"]
git-tree-sha1 = "f7be53659ab06ddc986428d3a9dcc95f6fa6705a"
uuid = "b5f81e59-6552-4d32-b1f0-c071b021bf89"
version = "0.2.2"

[[deps.IniFile]]
git-tree-sha1 = "f550e6e32074c939295eb5ea6de31849ac2c9625"
uuid = "83e8ac13-25f8-5344-8a64-a9f2b223428f"
version = "0.5.1"

[[deps.InlineStrings]]
deps = ["Parsers"]
git-tree-sha1 = "d19f9edd8c34760dca2de2b503f969d8700ed288"
uuid = "842dd82b-1e85-43dc-bf29-5d0ee9dffc48"
version = "1.1.4"

[[deps.InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"

[[deps.InverseFunctions]]
deps = ["Test"]
git-tree-sha1 = "49510dfcb407e572524ba94aeae2fced1f3feb0f"
uuid = "3587e190-3f89-42d0-90ee-14403ec27112"
version = "0.1.8"

[[deps.InvertedIndices]]
git-tree-sha1 = "bee5f1ef5bf65df56bdd2e40447590b272a5471f"
uuid = "41ab1584-1d38-5bbf-9106-f11c6c58b48f"
version = "1.1.0"

[[deps.IrrationalConstants]]
git-tree-sha1 = "7fd44fd4ff43fc60815f8e764c0f352b83c49151"
uuid = "92d709cd-6900-40b7-9082-c6be49f344b6"
version = "0.1.1"

[[deps.IteratorInterfaceExtensions]]
git-tree-sha1 = "a3f24677c21f5bbe9d2a714f95dcd58337fb2856"
uuid = "82899510-4779-5014-852e-03e436cf321d"
version = "1.0.0"

[[deps.JLD2]]
deps = ["FileIO", "MacroTools", "Mmap", "OrderedCollections", "Pkg", "Printf", "Reexport", "TranscodingStreams", "UUIDs"]
git-tree-sha1 = "0d0ad913e827d13c5e88a73f9333d7e33c424576"
uuid = "033835bb-8acc-5ee8-8aae-3f567f8a3819"
version = "0.4.24"

[[deps.JLFzf]]
deps = ["Pipe", "REPL", "Random", "fzf_jll"]
git-tree-sha1 = "f377670cda23b6b7c1c0b3893e37451c5c1a2185"
uuid = "1019f520-868f-41f5-a6de-eb00f4b6a39c"
version = "0.1.5"

[[deps.JLLWrappers]]
deps = ["Preferences"]
git-tree-sha1 = "abc9885a7ca2052a736a600f7fa66209f96506e1"
uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
version = "1.4.1"

[[deps.JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "3c837543ddb02250ef42f4738347454f95079d4e"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.3"

[[deps.JpegTurbo_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "b53380851c6e6664204efb2e62cd24fa5c47e4ba"
uuid = "aacddb02-875f-59d6-b918-886e6ef4fbf8"
version = "2.1.2+0"

[[deps.JuliaInterpreter]]
deps = ["CodeTracking", "InteractiveUtils", "Random", "UUIDs"]
git-tree-sha1 = "0f960b1404abb0b244c1ece579a0ec78d056a5d1"
uuid = "aa1ae85d-cabe-5617-a682-6adf51b2e16a"
version = "0.9.15"

[[deps.LAME_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "f6250b16881adf048549549fba48b1161acdac8c"
uuid = "c1c5ebd0-6772-5130-a774-d5fcae4a789d"
version = "3.100.1+0"

[[deps.LERC_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "bf36f528eec6634efc60d7ec062008f171071434"
uuid = "88015f11-f218-50d7-93a8-a6af411a945d"
version = "3.0.0+1"

[[deps.LZO_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "e5b909bcf985c5e2605737d2ce278ed791b89be6"
uuid = "dd4b983a-f0e5-5f8d-a1b7-129d4a5fb1ac"
version = "2.10.1+0"

[[deps.LaTeXStrings]]
git-tree-sha1 = "f2355693d6778a178ade15952b7ac47a4ff97996"
uuid = "b964fa9f-0449-5b57-a5c2-d3ea65f4040f"
version = "1.3.0"

[[deps.Latexify]]
deps = ["Formatting", "InteractiveUtils", "LaTeXStrings", "MacroTools", "Markdown", "OrderedCollections", "Printf", "Requires"]
git-tree-sha1 = "ab9aa169d2160129beb241cb2750ca499b4e90e9"
uuid = "23fbe1c1-3f47-55db-b15f-69d7ec21a316"
version = "0.15.17"

[[deps.LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"

[[deps.LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"

[[deps.LibGit2]]
deps = ["Base64", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"

[[deps.LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "MbedTLS_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"

[[deps.Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"

[[deps.Libffi_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "0b4a5d71f3e5200a7dff793393e09dfc2d874290"
uuid = "e9f186c6-92d2-5b65-8a66-fee21dc1b490"
version = "3.2.2+1"

[[deps.Libgcrypt_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libgpg_error_jll", "Pkg"]
git-tree-sha1 = "64613c82a59c120435c067c2b809fc61cf5166ae"
uuid = "d4300ac3-e22c-5743-9152-c294e39db1e4"
version = "1.8.7+0"

[[deps.Libglvnd_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll", "Xorg_libXext_jll"]
git-tree-sha1 = "7739f837d6447403596a75d19ed01fd08d6f56bf"
uuid = "7e76a0d4-f3c7-5321-8279-8d96eeed0f29"
version = "1.3.0+3"

[[deps.Libgpg_error_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "c333716e46366857753e273ce6a69ee0945a6db9"
uuid = "7add5ba3-2f88-524e-9cd5-f83b8a55f7b8"
version = "1.42.0+0"

[[deps.Libiconv_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "42b62845d70a619f063a7da093d995ec8e15e778"
uuid = "94ce4f54-9a6c-5748-9c1c-f9c7231a4531"
version = "1.16.1+1"

[[deps.Libmount_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "9c30530bf0effd46e15e0fdcf2b8636e78cbbd73"
uuid = "4b2f31a3-9ecc-558c-b454-b3730dcb73e9"
version = "2.35.0+0"

[[deps.Libtiff_jll]]
deps = ["Artifacts", "JLLWrappers", "JpegTurbo_jll", "LERC_jll", "Libdl", "Pkg", "Zlib_jll", "Zstd_jll"]
git-tree-sha1 = "3eb79b0ca5764d4799c06699573fd8f533259713"
uuid = "89763e89-9b03-5906-acba-b20f662cd828"
version = "4.4.0+0"

[[deps.Libuuid_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "7f3efec06033682db852f8b3bc3c1d2b0a0ab066"
uuid = "38a345b3-de98-5d2b-a5d3-14cd9215e700"
version = "2.36.0+0"

[[deps.LinearAlgebra]]
deps = ["Libdl", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"

[[deps.LogExpFunctions]]
deps = ["ChainRulesCore", "ChangesOfVariables", "DocStringExtensions", "InverseFunctions", "IrrationalConstants", "LinearAlgebra"]
git-tree-sha1 = "94d9c52ca447e23eac0c0f074effbcd38830deb5"
uuid = "2ab3a3ac-af41-5b50-aa03-7779005ae688"
version = "0.3.18"

[[deps.Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"

[[deps.LoggingExtras]]
deps = ["Dates", "Logging"]
git-tree-sha1 = "5d4d2d9904227b8bd66386c1138cf4d5ffa826bf"
uuid = "e6f89c97-d47a-5376-807f-9c37f3926c36"
version = "0.4.9"

[[deps.LoweredCodeUtils]]
deps = ["JuliaInterpreter"]
git-tree-sha1 = "dedbebe234e06e1ddad435f5c6f4b85cd8ce55f7"
uuid = "6f1432cf-f94c-5a45-995e-cdbf5db27b0b"
version = "2.2.2"

[[deps.MacroTools]]
deps = ["Markdown", "Random"]
git-tree-sha1 = "3d3e902b31198a27340d0bf00d6ac452866021cf"
uuid = "1914dd2f-81c6-5fcd-8719-6d5c9610ff09"
version = "0.5.9"

[[deps.Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"

[[deps.MbedTLS]]
deps = ["Dates", "MbedTLS_jll", "MozillaCACerts_jll", "Random", "Sockets"]
git-tree-sha1 = "6872f9594ff273da6d13c7c1a1545d5a8c7d0c1c"
uuid = "739be429-bea8-5141-9913-cc70e7f3736d"
version = "1.1.6"

[[deps.MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"

[[deps.Measures]]
git-tree-sha1 = "e498ddeee6f9fdb4551ce855a46f54dbd900245f"
uuid = "442fdcdd-2543-5da2-b0f3-8c86c306513e"
version = "0.3.1"

[[deps.Missings]]
deps = ["DataAPI"]
git-tree-sha1 = "bf210ce90b6c9eed32d25dbcae1ebc565df2687f"
uuid = "e1d29d7a-bbdc-5cf2-9ac0-f12de2c33e28"
version = "1.0.2"

[[deps.Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"

[[deps.MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"

[[deps.NaNMath]]
deps = ["OpenLibm_jll"]
git-tree-sha1 = "a7c3d1da1189a1c2fe843a3bfa04d18d20eb3211"
uuid = "77ba4419-2d1f-58cd-9bb1-8ffee604a2e3"
version = "1.0.1"

[[deps.NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"

[[deps.Ogg_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "887579a3eb005446d514ab7aeac5d1d027658b8f"
uuid = "e7412a2a-1a6e-54c0-be00-318e2571c051"
version = "1.3.5+1"

[[deps.OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"

[[deps.OpenLibm_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "05823500-19ac-5b8b-9628-191a04bc5112"

[[deps.OpenSSL]]
deps = ["BitFlags", "Dates", "MozillaCACerts_jll", "OpenSSL_jll", "Sockets"]
git-tree-sha1 = "02be9f845cb58c2d6029a6d5f67f4e0af3237814"
uuid = "4d8831e6-92b7-49fb-bdf8-b643e874388c"
version = "1.1.3"

[[deps.OpenSSL_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "e60321e3f2616584ff98f0a4f18d98ae6f89bbb3"
uuid = "458c3c95-2e84-50aa-8efc-19380b2a3a95"
version = "1.1.17+0"

[[deps.OpenSpecFun_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "13652491f6856acfd2db29360e1bbcd4565d04f1"
uuid = "efe28fd5-8261-553b-a9e1-b2916fc3738e"
version = "0.5.5+0"

[[deps.Opus_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "51a08fb14ec28da2ec7a927c4337e4332c2a4720"
uuid = "91d4177d-7536-5919-b921-800302f37372"
version = "1.3.2+0"

[[deps.OrderedCollections]]
git-tree-sha1 = "85f8e6578bf1f9ee0d11e7bb1b1456435479d47c"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "1.4.1"

[[deps.PCRE2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "efcefdf7-47ab-520b-bdef-62a2eaa19f15"

[[deps.Parsers]]
deps = ["Dates"]
git-tree-sha1 = "3d5bf43e3e8b412656404ed9466f1dcbf7c50269"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.4.0"

[[deps.Pipe]]
git-tree-sha1 = "6842804e7867b115ca9de748a0cf6b364523c16d"
uuid = "b98c9c47-44ae-5843-9183-064241ee97a0"
version = "1.3.0"

[[deps.Pixman_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "b4f5d02549a10e20780a24fce72bea96b6329e29"
uuid = "30392449-352a-5448-841d-b1acce4e97dc"
version = "0.40.1+0"

[[deps.Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "REPL", "Random", "SHA", "Serialization", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"

[[deps.PlotThemes]]
deps = ["PlotUtils", "Statistics"]
git-tree-sha1 = "8162b2f8547bc23876edd0c5181b27702ae58dce"
uuid = "ccf2f8ad-2431-5c83-bf29-c5338b663b6a"
version = "3.0.0"

[[deps.PlotUtils]]
deps = ["ColorSchemes", "Colors", "Dates", "Printf", "Random", "Reexport", "SnoopPrecompile", "Statistics"]
git-tree-sha1 = "21303256d239f6b484977314674aef4bb1fe4420"
uuid = "995b91a9-d308-5afd-9ec6-746e21dbc043"
version = "1.3.1"

[[deps.Plots]]
deps = ["Base64", "Contour", "Dates", "Downloads", "FFMPEG", "FixedPointNumbers", "GR", "JLFzf", "JSON", "LaTeXStrings", "Latexify", "LinearAlgebra", "Measures", "NaNMath", "Pkg", "PlotThemes", "PlotUtils", "Printf", "REPL", "Random", "RecipesBase", "RecipesPipeline", "Reexport", "RelocatableFolders", "Requires", "Scratch", "Showoff", "SnoopPrecompile", "SparseArrays", "Statistics", "StatsBase", "UUIDs", "UnicodeFun", "Unzip"]
git-tree-sha1 = "f60a3090028cdf16b33a62f97eaedf67a6509824"
uuid = "91a5bcdd-55d7-5caf-9e0b-520d859cae80"
version = "1.35.0"

[[deps.PlutoHooks]]
deps = ["InteractiveUtils", "Markdown", "UUIDs"]
git-tree-sha1 = "072cdf20c9b0507fdd977d7d246d90030609674b"
uuid = "0ff47ea0-7a50-410d-8455-4348d5de0774"
version = "0.0.5"

[[deps.PlutoLinks]]
deps = ["FileWatching", "InteractiveUtils", "Markdown", "PlutoHooks", "Revise", "UUIDs"]
git-tree-sha1 = "0e8bcc235ec8367a8e9648d48325ff00e4b0a545"
uuid = "0ff47ea0-7a50-410d-8455-4348d5de0420"
version = "0.1.5"

[[deps.PlutoTeachingTools]]
deps = ["Downloads", "HypertextLiteral", "LaTeXStrings", "Latexify", "Markdown", "PlutoLinks", "PlutoUI", "Random"]
git-tree-sha1 = "d8be3432505c2febcea02f44e5f4396fae017503"
uuid = "661c6b06-c737-4d37-b85c-46df65de6f69"
version = "0.2.3"

[[deps.PlutoUI]]
deps = ["AbstractPlutoDingetjes", "Base64", "ColorTypes", "Dates", "Hyperscript", "HypertextLiteral", "IOCapture", "InteractiveUtils", "JSON", "Logging", "Markdown", "Random", "Reexport", "UUIDs"]
git-tree-sha1 = "2777a5c2c91b3145f5aa75b61bb4c2eb38797136"
uuid = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
version = "0.7.43"

[[deps.PooledArrays]]
deps = ["DataAPI", "Future"]
git-tree-sha1 = "a6062fe4063cdafe78f4a0a81cfffb89721b30e7"
uuid = "2dfb63ee-cc39-5dd5-95bd-886bf059d720"
version = "1.4.2"

[[deps.Preferences]]
deps = ["TOML"]
git-tree-sha1 = "47e5f437cc0e7ef2ce8406ce1e7e24d44915f88d"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.3.0"

[[deps.PrettyTables]]
deps = ["Crayons", "Formatting", "Markdown", "Reexport", "Tables"]
git-tree-sha1 = "dfb54c4e414caa595a1f2ed759b160f5a3ddcba5"
uuid = "08abe8d2-0d0c-5749-adfa-8a2ac140af0d"
version = "1.3.1"

[[deps.Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"

[[deps.Qt5Base_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Fontconfig_jll", "Glib_jll", "JLLWrappers", "Libdl", "Libglvnd_jll", "OpenSSL_jll", "Pkg", "Xorg_libXext_jll", "Xorg_libxcb_jll", "Xorg_xcb_util_image_jll", "Xorg_xcb_util_keysyms_jll", "Xorg_xcb_util_renderutil_jll", "Xorg_xcb_util_wm_jll", "Zlib_jll", "xkbcommon_jll"]
git-tree-sha1 = "c6c0f690d0cc7caddb74cef7aa847b824a16b256"
uuid = "ea2cea3b-5b76-57ae-a6ef-0a8af62496e1"
version = "5.15.3+1"

[[deps.REPL]]
deps = ["InteractiveUtils", "Markdown", "Sockets", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"

[[deps.Random]]
deps = ["SHA", "Serialization"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[[deps.RecipesBase]]
deps = ["SnoopPrecompile"]
git-tree-sha1 = "612a4d76ad98e9722c8ba387614539155a59e30c"
uuid = "3cdcf5f2-1ef4-517c-9805-6587b60abb01"
version = "1.3.0"

[[deps.RecipesPipeline]]
deps = ["Dates", "NaNMath", "PlotUtils", "RecipesBase"]
git-tree-sha1 = "017f217e647cf20b0081b9be938b78c3443356a0"
uuid = "01d81517-befc-4cb6-b9ec-a95719d0359c"
version = "0.6.6"

[[deps.Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[deps.RelocatableFolders]]
deps = ["SHA", "Scratch"]
git-tree-sha1 = "90bc7a7c96410424509e4263e277e43250c05691"
uuid = "05181044-ff0b-4ac5-8273-598c1e38db00"
version = "1.0.0"

[[deps.Requires]]
deps = ["UUIDs"]
git-tree-sha1 = "838a3a4188e2ded87a4f9f184b4b0d78a1e91cb7"
uuid = "ae029012-a4dd-5104-9daa-d747884805df"
version = "1.3.0"

[[deps.Revise]]
deps = ["CodeTracking", "Distributed", "FileWatching", "JuliaInterpreter", "LibGit2", "LoweredCodeUtils", "OrderedCollections", "Pkg", "REPL", "Requires", "UUIDs", "Unicode"]
git-tree-sha1 = "dad726963ecea2d8a81e26286f625aee09a91b7c"
uuid = "295af30f-e4ad-537b-8983-00126c2a3abe"
version = "3.4.0"

[[deps.SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"

[[deps.Scratch]]
deps = ["Dates"]
git-tree-sha1 = "f94f779c94e58bf9ea243e77a37e16d9de9126bd"
uuid = "6c6a2e73-6563-6170-7368-637461726353"
version = "1.1.1"

[[deps.SentinelArrays]]
deps = ["Dates", "Random"]
git-tree-sha1 = "c0f56940fc967f3d5efed58ba829747af5f8b586"
uuid = "91c51154-3ec4-41a3-a24f-3f23e20d615c"
version = "1.3.15"

[[deps.Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[deps.Showoff]]
deps = ["Dates", "Grisu"]
git-tree-sha1 = "91eddf657aca81df9ae6ceb20b959ae5653ad1de"
uuid = "992d4aef-0814-514b-bc4d-f2e9a6c4116f"
version = "1.0.3"

[[deps.SimpleBufferStream]]
git-tree-sha1 = "874e8867b33a00e784c8a7e4b60afe9e037b74e1"
uuid = "777ac1f9-54b0-4bf8-805c-2214025038e7"
version = "1.1.0"

[[deps.SnoopPrecompile]]
git-tree-sha1 = "f604441450a3c0569830946e5b33b78c928e1a85"
uuid = "66db9d55-30c0-4569-8b51-7e840670fc0c"
version = "1.0.1"

[[deps.Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"

[[deps.SortingAlgorithms]]
deps = ["DataStructures"]
git-tree-sha1 = "b3363d7460f7d098ca0912c69b082f75625d7508"
uuid = "a2af1166-a08f-5f64-846c-94a0d3cef48c"
version = "1.0.1"

[[deps.SparseArrays]]
deps = ["LinearAlgebra", "Random"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[deps.SpecialFunctions]]
deps = ["ChainRulesCore", "IrrationalConstants", "LogExpFunctions", "OpenLibm_jll", "OpenSpecFun_jll"]
git-tree-sha1 = "d75bda01f8c31ebb72df80a46c88b25d1c79c56d"
uuid = "276daf66-3868-5448-9aa4-cd146d93841b"
version = "2.1.7"

[[deps.Statistics]]
deps = ["LinearAlgebra", "SparseArrays"]
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[[deps.StatsAPI]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "f9af7f195fb13589dd2e2d57fdb401717d2eb1f6"
uuid = "82ae8749-77ed-4fe6-ae5f-f523153014b0"
version = "1.5.0"

[[deps.StatsBase]]
deps = ["DataAPI", "DataStructures", "LinearAlgebra", "LogExpFunctions", "Missings", "Printf", "Random", "SortingAlgorithms", "SparseArrays", "Statistics", "StatsAPI"]
git-tree-sha1 = "d1bf48bfcc554a3761a133fe3a9bb01488e06916"
uuid = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"
version = "0.33.21"

[[deps.TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"

[[deps.TableTraits]]
deps = ["IteratorInterfaceExtensions"]
git-tree-sha1 = "c06b2f539df1c6efa794486abfb6ed2022561a39"
uuid = "3783bdb8-4a98-5b6b-af9a-565f29a5fe9c"
version = "1.0.1"

[[deps.Tables]]
deps = ["DataAPI", "DataValueInterfaces", "IteratorInterfaceExtensions", "LinearAlgebra", "OrderedCollections", "TableTraits", "Test"]
git-tree-sha1 = "2d7164f7b8a066bcfa6224e67736ce0eb54aef5b"
uuid = "bd369af6-aec1-5ad0-b16a-f7cc5008161c"
version = "1.9.0"

[[deps.Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"

[[deps.TensorCore]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "1feb45f88d133a655e001435632f019a9a1bcdb6"
uuid = "62fd8b95-f654-4bbd-a8a5-9c27f68ccd50"
version = "0.1.1"

[[deps.Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[deps.TranscodingStreams]]
deps = ["Random", "Test"]
git-tree-sha1 = "8a75929dcd3c38611db2f8d08546decb514fcadf"
uuid = "3bb67fe8-82b1-5028-8e26-92a6c54297fa"
version = "0.9.9"

[[deps.Tricks]]
git-tree-sha1 = "6bac775f2d42a611cdfcd1fb217ee719630c4175"
uuid = "410a4b4d-49e4-4fbc-ab6d-cb71b17b3775"
version = "0.1.6"

[[deps.URIs]]
git-tree-sha1 = "e59ecc5a41b000fa94423a578d29290c7266fc10"
uuid = "5c2747f8-b7ea-4ff2-ba2e-563bfd36b1d4"
version = "1.4.0"

[[deps.UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"

[[deps.Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"

[[deps.UnicodeFun]]
deps = ["REPL"]
git-tree-sha1 = "53915e50200959667e78a92a418594b428dffddf"
uuid = "1cfade01-22cf-5700-b092-accc4b62d6e1"
version = "0.4.1"

[[deps.Unzip]]
git-tree-sha1 = "ca0969166a028236229f63514992fc073799bb78"
uuid = "41fe7b60-77ed-43a1-b4f0-825fd5a5650d"
version = "0.2.0"

[[deps.Wayland_jll]]
deps = ["Artifacts", "Expat_jll", "JLLWrappers", "Libdl", "Libffi_jll", "Pkg", "XML2_jll"]
git-tree-sha1 = "3e61f0b86f90dacb0bc0e73a0c5a83f6a8636e23"
uuid = "a2964d1f-97da-50d4-b82a-358c7fce9d89"
version = "1.19.0+0"

[[deps.Wayland_protocols_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "4528479aa01ee1b3b4cd0e6faef0e04cf16466da"
uuid = "2381bf8a-dfd0-557d-9999-79630e7b1b91"
version = "1.25.0+0"

[[deps.WeakRefStrings]]
deps = ["DataAPI", "InlineStrings", "Parsers"]
git-tree-sha1 = "b1be2855ed9ed8eac54e5caff2afcdb442d52c23"
uuid = "ea10d353-3f73-51f8-a26c-33c1cb351aa5"
version = "1.4.2"

[[deps.XML2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libiconv_jll", "Pkg", "Zlib_jll"]
git-tree-sha1 = "58443b63fb7e465a8a7210828c91c08b92132dff"
uuid = "02c8fc9c-b97f-50b9-bbe4-9be30ff0a78a"
version = "2.9.14+0"

[[deps.XSLT_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libgcrypt_jll", "Libgpg_error_jll", "Libiconv_jll", "Pkg", "XML2_jll", "Zlib_jll"]
git-tree-sha1 = "91844873c4085240b95e795f692c4cec4d805f8a"
uuid = "aed1982a-8fda-507f-9586-7b0439959a61"
version = "1.1.34+0"

[[deps.Xorg_libX11_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libxcb_jll", "Xorg_xtrans_jll"]
git-tree-sha1 = "5be649d550f3f4b95308bf0183b82e2582876527"
uuid = "4f6342f7-b3d2-589e-9d20-edeb45f2b2bc"
version = "1.6.9+4"

[[deps.Xorg_libXau_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "4e490d5c960c314f33885790ed410ff3a94ce67e"
uuid = "0c0b7dd1-d40b-584c-a123-a41640f87eec"
version = "1.0.9+4"

[[deps.Xorg_libXcursor_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXfixes_jll", "Xorg_libXrender_jll"]
git-tree-sha1 = "12e0eb3bc634fa2080c1c37fccf56f7c22989afd"
uuid = "935fb764-8cf2-53bf-bb30-45bb1f8bf724"
version = "1.2.0+4"

[[deps.Xorg_libXdmcp_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "4fe47bd2247248125c428978740e18a681372dd4"
uuid = "a3789734-cfe1-5b06-b2d0-1dd0d9d62d05"
version = "1.1.3+4"

[[deps.Xorg_libXext_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "b7c0aa8c376b31e4852b360222848637f481f8c3"
uuid = "1082639a-0dae-5f34-9b06-72781eeb8cb3"
version = "1.3.4+4"

[[deps.Xorg_libXfixes_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "0e0dc7431e7a0587559f9294aeec269471c991a4"
uuid = "d091e8ba-531a-589c-9de9-94069b037ed8"
version = "5.0.3+4"

[[deps.Xorg_libXi_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXext_jll", "Xorg_libXfixes_jll"]
git-tree-sha1 = "89b52bc2160aadc84d707093930ef0bffa641246"
uuid = "a51aa0fd-4e3c-5386-b890-e753decda492"
version = "1.7.10+4"

[[deps.Xorg_libXinerama_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXext_jll"]
git-tree-sha1 = "26be8b1c342929259317d8b9f7b53bf2bb73b123"
uuid = "d1454406-59df-5ea1-beac-c340f2130bc3"
version = "1.1.4+4"

[[deps.Xorg_libXrandr_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXext_jll", "Xorg_libXrender_jll"]
git-tree-sha1 = "34cea83cb726fb58f325887bf0612c6b3fb17631"
uuid = "ec84b674-ba8e-5d96-8ba1-2a689ba10484"
version = "1.5.2+4"

[[deps.Xorg_libXrender_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "19560f30fd49f4d4efbe7002a1037f8c43d43b96"
uuid = "ea2f1a96-1ddc-540d-b46f-429655e07cfa"
version = "0.9.10+4"

[[deps.Xorg_libpthread_stubs_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "6783737e45d3c59a4a4c4091f5f88cdcf0908cbb"
uuid = "14d82f49-176c-5ed1-bb49-ad3f5cbd8c74"
version = "0.1.0+3"

[[deps.Xorg_libxcb_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "XSLT_jll", "Xorg_libXau_jll", "Xorg_libXdmcp_jll", "Xorg_libpthread_stubs_jll"]
git-tree-sha1 = "daf17f441228e7a3833846cd048892861cff16d6"
uuid = "c7cfdc94-dc32-55de-ac96-5a1b8d977c5b"
version = "1.13.0+3"

[[deps.Xorg_libxkbfile_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "926af861744212db0eb001d9e40b5d16292080b2"
uuid = "cc61e674-0454-545c-8b26-ed2c68acab7a"
version = "1.1.0+4"

[[deps.Xorg_xcb_util_image_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "0fab0a40349ba1cba2c1da699243396ff8e94b97"
uuid = "12413925-8142-5f55-bb0e-6d7ca50bb09b"
version = "0.4.0+1"

[[deps.Xorg_xcb_util_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libxcb_jll"]
git-tree-sha1 = "e7fd7b2881fa2eaa72717420894d3938177862d1"
uuid = "2def613f-5ad1-5310-b15b-b15d46f528f5"
version = "0.4.0+1"

[[deps.Xorg_xcb_util_keysyms_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "d1151e2c45a544f32441a567d1690e701ec89b00"
uuid = "975044d2-76e6-5fbe-bf08-97ce7c6574c7"
version = "0.4.0+1"

[[deps.Xorg_xcb_util_renderutil_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "dfd7a8f38d4613b6a575253b3174dd991ca6183e"
uuid = "0d47668e-0667-5a69-a72c-f761630bfb7e"
version = "0.3.9+1"

[[deps.Xorg_xcb_util_wm_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "e78d10aab01a4a154142c5006ed44fd9e8e31b67"
uuid = "c22f9ab0-d5fe-5066-847c-f4bb1cd4e361"
version = "0.4.1+1"

[[deps.Xorg_xkbcomp_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libxkbfile_jll"]
git-tree-sha1 = "4bcbf660f6c2e714f87e960a171b119d06ee163b"
uuid = "35661453-b289-5fab-8a00-3d9160c6a3a4"
version = "1.4.2+4"

[[deps.Xorg_xkeyboard_config_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xkbcomp_jll"]
git-tree-sha1 = "5c8424f8a67c3f2209646d4425f3d415fee5931d"
uuid = "33bec58e-1273-512f-9401-5d533626f822"
version = "2.27.0+4"

[[deps.Xorg_xtrans_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "79c31e7844f6ecf779705fbc12146eb190b7d845"
uuid = "c5fb5394-a638-5e4d-96e5-b29de1b5cf10"
version = "1.4.0+3"

[[deps.Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"

[[deps.Zstd_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "e45044cd873ded54b6a5bac0eb5c971392cf1927"
uuid = "3161d3a3-bdf6-5164-811a-617609db77b4"
version = "1.5.2+0"

[[deps.fzf_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "868e669ccb12ba16eaf50cb2957ee2ff61261c56"
uuid = "214eeab7-80f7-51ab-84ad-2988db7cef09"
version = "0.29.0+0"

[[deps.libaom_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "3a2ea60308f0996d26f1e5354e10c24e9ef905d4"
uuid = "a4ae2306-e953-59d6-aa16-d00cac43593b"
version = "3.4.0+0"

[[deps.libass_jll]]
deps = ["Artifacts", "Bzip2_jll", "FreeType2_jll", "FriBidi_jll", "HarfBuzz_jll", "JLLWrappers", "Libdl", "Pkg", "Zlib_jll"]
git-tree-sha1 = "5982a94fcba20f02f42ace44b9894ee2b140fe47"
uuid = "0ac62f75-1d6f-5e53-bd7c-93b484bb37c0"
version = "0.15.1+0"

[[deps.libblastrampoline_jll]]
deps = ["Artifacts", "Libdl", "OpenBLAS_jll"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"

[[deps.libfdk_aac_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "daacc84a041563f965be61859a36e17c4e4fcd55"
uuid = "f638f0a6-7fb0-5443-88ba-1cc74229b280"
version = "2.0.2+0"

[[deps.libpng_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Zlib_jll"]
git-tree-sha1 = "94d180a6d2b5e55e447e2d27a29ed04fe79eb30c"
uuid = "b53b4c65-9356-5827-b1ea-8c7a1a84506f"
version = "1.6.38+0"

[[deps.libvorbis_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Ogg_jll", "Pkg"]
git-tree-sha1 = "b910cb81ef3fe6e78bf6acee440bda86fd6ae00c"
uuid = "f27f6e37-5d2b-51aa-960f-b287f2bc3b7a"
version = "1.3.7+1"

[[deps.nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"

[[deps.p7zip_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"

[[deps.x264_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "4fea590b89e6ec504593146bf8b988b2c00922b2"
uuid = "1270edf5-f2f9-52d2-97e9-ab00b5d0237a"
version = "2021.5.5+0"

[[deps.x265_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "ee567a171cce03570d77ad3a43e90218e38937a9"
uuid = "dfaa095f-4041-5dcd-9319-2fabd8486b76"
version = "3.5.0+0"

[[deps.xkbcommon_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Wayland_jll", "Wayland_protocols_jll", "Xorg_libxcb_jll", "Xorg_xkeyboard_config_jll"]
git-tree-sha1 = "9ebfc140cc56e8c2156a15ceac2f0302e327ac0a"
uuid = "d8fb68d0-12a3-5cfd-a85a-d49703b185fd"
version = "1.4.1+0"
"""

# ╔═╡ Cell order:
# ╟─e0e60e09-3808-4d6b-a773-6ba59c02f517
# ╟─4745a620-5650-4c83-b4c2-9ab4572bcb66
# ╟─8c1d81ab-d215-4972-afeb-7e00bf6063c2
# ╟─7e132d9d-a159-4973-b8a3-36abda56249a
# ╠═5be68976-141c-47f9-b2ad-1c457bb434eb
# ╠═fc15fc5e-0fe9-4468-9af3-e389b16b455c
# ╟─c80b32e9-53f1-4027-a878-f949a7acea41
# ╠═d07c4aac-616c-484c-8431-130d68869b00
# ╟─1ba1db1f-4e77-448c-bde0-82d4c0a39d31
# ╟─09b660ee-c075-4139-a34f-e3daaa34ca9e
# ╟─1607eac9-e76f-4d1f-a9ce-981ce3be9bea
# ╠═f27e1e8f-15eb-4754-a94c-7f37c54b871e
# ╟─80f02c3a-6751-48df-92ec-13f5c7d8c71e
# ╟─624c9038-3008-4e78-a149-60796dacf9c0
# ╠═047af20e-15af-46fa-af7f-954048324ee3
# ╠═7506f029-aa07-449f-bb8f-998a15d7d298
# ╟─4d633b2b-ec20-49cc-9571-5ff64dc306b0
# ╟─34dc2f22-fa58-414c-9376-7375cc8fdb71
# ╟─191ba96e-2573-4bc1-a352-46a66e0a5c4f
# ╠═82a757ad-566d-4c1d-8b3d-366ffd980fb4
# ╟─8722f1a5-ebbc-456f-bd5b-3735d8786373
# ╟─7c258a60-f74d-49d1-8a0f-cf04f47d1811
# ╟─76dfb5f5-2eeb-4fa9-9bb0-dfabe61f9c8d
# ╠═7bfffe60-cba0-41af-8487-b700f5c2d77f
# ╟─ec40dba4-7217-4185-99f5-d821bdab036c
# ╟─98e31c27-5401-4e28-93b9-a46660152a59
# ╠═da378686-45c6-40c3-99ad-2fb864dd6f73
# ╠═66b27cce-c654-4b18-b29f-8d86b9f5b2be
# ╟─29999a62-7a8a-4dd3-9201-fbec61aeb5de
# ╟─5df124c1-b4b4-4930-b1f4-25912bb807b0
# ╟─69d5aa99-83d7-4cbc-8b2b-1175907aff34
# ╟─5eaaf547-1244-4b6a-a3f1-e46092864305
# ╠═507e1516-5433-49eb-831d-32426f30895e
# ╟─eac67cc9-754b-4f7d-add8-93900a1b5b49
# ╠═cc968c96-7f90-47d9-af7d-24b79556b5d6
# ╟─02c91f91-8da8-49c9-bd81-00c0233b47b3
# ╟─1fd95fea-2587-4d19-a1d4-aa6b3744a773
# ╟─945f5a55-3026-4497-9ece-8af878c87788
# ╠═57397ee4-9efc-48b3-b640-d2b7a10da633
# ╟─8059a6a3-384a-4344-8a23-650ee0be10c2
# ╟─64224c6b-c5a0-44f2-b2a0-7f77759cb848
# ╟─f5b93929-2c59-4360-8c41-97a1324ba455
# ╠═122196fa-45ca-4031-85eb-4afd4782de9e
# ╟─e9dc1456-616b-4e4b-b209-9f6ba4c48607
# ╠═3e550b71-4750-460b-be18-911a848a8f49
# ╟─f15d37a7-d962-4da0-977f-76729a3313be
# ╟─28f195c4-4f61-4873-85d6-b4e3aaa3660f
# ╠═3837e439-250b-4577-b0d7-93352ec19f6e
# ╟─6c147ad6-95b4-4008-bd9b-72f1ece8de5c
# ╟─9b411269-f1bc-4e1b-93c8-78f5407597cb
# ╟─7cda896c-59e4-4c08-8237-7869589604ba
# ╟─afd68362-8459-4994-bdc7-1338640a4543
# ╟─28af4229-5de4-47ef-9fc8-4033901c50b8
# ╟─8bfde242-e2ec-4556-8b54-bbafbe1b1ddc
# ╟─ced8a0e5-b6e7-4a72-a296-d0ae3865a6ee
# ╟─86728419-ebb4-4d90-88bb-346c763e0fb9
# ╟─b8a2c1a0-381e-47e0-acc5-65ccd905d519
# ╠═ca62f6ad-1dd5-4ca5-a957-d82e38198b11
# ╠═5a2b064c-21f3-4ce6-a3e5-ab0a9f98dd5c
# ╟─570fd826-23fd-46ee-bdb4-58fb0c45719a
# ╟─691410bb-0472-4800-a90d-29ddf947de3e
# ╟─6143bcd4-32b7-48c3-8b88-4b615d20f1b3
# ╠═55eaadf5-d352-4673-a56c-effb952093dc
# ╟─107a432d-39e8-4db2-9820-a57a88589d6e
# ╟─56124135-23ff-49cd-8a84-c22f178533c6
# ╠═8856674a-6b72-4dfa-9753-0dcd9e578068
# ╟─4c17241a-1f1a-4a49-8a13-2deb0e266ce6
# ╟─6a35e827-d987-4136-b33f-1c7a403e1ce4
# ╟─ad72b21c-f5ec-4dab-8ccf-d544eb006ec1
# ╟─e6c93876-e832-4f28-9777-b9602d5204f9
# ╟─9e10abc3-7722-4d7d-b2d1-9baf6eea94ba
# ╟─1de771de-f32b-4f32-8dbe-c56295fd935d
# ╠═b800d43d-e688-4059-8aa2-0fddb45e2940
# ╟─0eb83f4b-64cc-4864-8a80-9305da59e82f
# ╟─7a17bf14-b749-4136-bfde-e5599a8738be
# ╟─ec00c9a5-2140-4b34-bab4-9a89e09eecdc
# ╟─bf2f48b7-fde9-41df-83e8-26ee557b6f1c
# ╟─8cbb1c90-bd94-44b5-80b6-81d38f3e6252
# ╠═c3065acf-6205-455f-ba74-ca51f3f6761b
# ╟─fc01d57f-c90b-4231-96be-ddd48656d55e
# ╠═e05f16d6-eb50-49a9-bf14-95d63c9da7ff
# ╟─5cadfa6c-1e6b-4450-ba4a-4a43a6a31fa7
# ╠═c7373630-aab0-45a3-b9b9-5ccbe8785ff1
# ╟─98bac9c4-28e4-46aa-ab82-4c5017bbdfa4
# ╟─91957d9b-ce75-4249-b125-e312c0a2a454
# ╠═cdacd651-19af-41d5-a5c0-75ffab32300c
# ╟─7c4c83de-48b4-474d-9995-ea86ed06af6d
# ╟─9e3e9fe8-7ab9-4b90-8596-f225a44d73c4
# ╟─b9e16183-4eb5-468d-9486-7a3b6571777c
# ╠═a63af23d-5408-4815-b898-1ab62670d37a
# ╟─4960aac7-29e3-415b-bbd0-2ecdca26fd46
# ╟─1f39b2d0-7825-4e6f-abc1-028b4d59b377
# ╟─c272215b-6d9a-4be5-ab7b-bb17319cd294
# ╠═d5e4f29d-ee33-4fac-afd8-2d6e69f611ac
# ╟─3314b839-293c-4731-95b5-61b9b25613db
# ╟─3b232365-f2fe-4edb-a39f-3e37c8cbb666
# ╟─1992595f-9976-4b18-bf9c-df8a73d30dc8
# ╟─ed7fe6ad-bc74-42b8-8348-613541afcacf
# ╟─6046dff3-8725-4252-8516-2cd0dfc14f6f
# ╠═d69bc955-6119-4327-bfd4-ca4723bbaac1
# ╟─e00bdaa1-fa0a-404d-9da2-595c416a2097
# ╟─bf659991-1ed2-4bef-81ef-9f04bd3620f8
# ╟─8def87d2-f10b-4a82-b353-a6477eeead9b
# ╟─c74b3105-f480-4688-b85f-3e7dff70da3b
# ╠═55438c09-1d94-4ff7-90c3-0cc6064a091e
# ╟─1004feae-cf1a-4ecf-b443-34f5da22f4ec
# ╟─2ffd6e61-2fd2-4f91-9ebb-9b67183803b6
# ╟─bcc796c9-db11-4a09-a5f9-215127ac0938
# ╟─7790b2e0-36a3-44c5-aa69-83a146ca7799
# ╟─29415ddc-e002-4f56-a169-95f7b1c36be9
# ╟─fb23d6c6-b812-4fe1-b224-0014bedbd43f
# ╠═ac87ced2-986f-4e6c-80b2-104b25c171c2
# ╟─14cca8ce-cc61-4fae-b871-21c3fd23d0ea
# ╟─28fc8de4-749b-4093-b32f-c398f8d27d3d
# ╟─57b422e5-0ad0-4674-bdd3-a8358bc7aaeb
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
