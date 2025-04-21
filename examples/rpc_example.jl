"""
Example of using the RPC system for a simulated data processing service.

This demonstrates:
1. Creating a server with realistic data processing functions
2. Creating a client that calls these functions
3. Using the RPC system for both synchronous and asynchronous processing
"""

using Dates, Statistics, Random
using Revise
import RPC: RPCServer, RPCClient

#=
Server-side implementation
=#

# Simulate a database with some time series data
struct DataPoint
	timestamp::DateTime
	value::Float64
end

# In-memory database (in a real app, this would be persistent)
const time_series_db = Dict{Symbol, Vector{DataPoint}}()

# Initialize with some sample data
function init_sample_data()
	Random.seed!(42)
	
	# Create time series for temperature sensors
	for location in [:living_room, :kitchen, :bedroom, :outside]
		# Create a week of hourly temperature readings
		start_time = DateTime(2023, 1, 1)
		
		# Base temperature and daily variation depends on location
		base_temp = location == :outside ? 10.0 : 22.0
		daily_var = location == :outside ? 15.0 : 3.0
		
		# Create the time series
		series = DataPoint[]
		for hour in 0:168  # One week of hours
			timestamp = start_time + Hour(hour)
			
			# Daily cycle + some random noise
			day_progress = (hour % 24) / 24.0
			daily_factor = sin(2π * (day_progress - 0.25))
			temp = base_temp + daily_var * daily_factor + rand(-1.0:0.1:1.0)
			
			push!(series, DataPoint(timestamp, temp))
		end
		
		time_series_db[location] = series
	end
end

# Function to get data for a specific sensor
function get_sensor_data(sensor_id::Symbol)
	if !haskey(time_series_db, sensor_id)
		error("Sensor $sensor_id not found")
	end
	return time_series_db[sensor_id]
end

# Function to get data for a specific time range
function get_data_in_range(sensor_id::Symbol, start_time::DateTime, end_time::DateTime)
	if !haskey(time_series_db, sensor_id)
		error("Sensor $sensor_id not found")
	end
	
	# Filter data points in the given range
	data = time_series_db[sensor_id]
	return filter(p -> start_time <= p.timestamp <= end_time, data)
end

# Calculate statistics for a sensor
function calculate_stats(sensor_id::Symbol)
	if !haskey(time_series_db, sensor_id)
		error("Sensor $sensor_id not found")
	end
	
	data = time_series_db[sensor_id]
	values = [p.value for p in data]
	
	return (
		min = minimum(values),
		max = maximum(values),
		mean = mean(values),
		median = median(values),
		std = std(values)
	)
end

# Process a batch job that takes some time
function process_batch_job(job_name::String, duration::Float64)
	@info "Starting batch job: $job_name (will take $duration seconds)"
	sleep(duration)  # Simulate processing time
	return "Batch job '$job_name' completed successfully at $(now())"
end

# Register functions with RPC server
function start_data_server()
	
	# Initialize sample data
	init_sample_data()
	
	# Register functions
	RPCServer.@rpc_export get_sensor_data
	RPCServer.@rpc_export get_data_in_range
	RPCServer.@rpc_export calculate_stats
	RPCServer.@rpc_export process_batch_job
	
	# Start the server
	RPCServer.start_server()
	@info "Data processing server started"
end

#=
Client-side implementation
=#

function run_client()
	
	# Connect to server
	RPCClient.connect()
	@info "Connected to data processing server"
	
	# Import remote functions
	RPCClient.@rpc_import get_sensor_data
	RPCClient.@rpc_import get_data_in_range
	RPCClient.@rpc_import calculate_stats
	RPCClient.@rpc_import process_batch_job
	
	# Get all available sensors (by getting their data)
	living_room_data = remote_get_sensor_data(:living_room)
	@info "Retrieved $(length(living_room_data)) data points for living room"
	
	# Calculate statistics for each sensor
	for sensor_id in [:living_room, :kitchen, :bedroom, :outside]
		stats = remote_calculate_stats(sensor_id)
		@info "Statistics for $sensor_id: min=$(stats.min)°C, max=$(stats.max)°C, mean=$(stats.mean)°C"
	end
	
	# Get data for a specific time range
	start_time = DateTime(2023, 1, 3)
	end_time = DateTime(2023, 1, 4)
	outside_range_data = remote_get_data_in_range(:outside, start_time, end_time)
	@info "Got $(length(outside_range_data)) outside temperature readings between $start_time and $end_time"
	
	# Start some batch jobs in parallel
	@info "Starting batch jobs in parallel..."
	tasks = []
	for i in 1:3
		job_name = "Data analysis job $i"
		t = @async begin
			result = remote_process_batch_job(job_name, 2.0)
			@info "Result: $result"
			return result
		end
		push!(tasks, t)
	end
	
	# Wait for all batch jobs to complete
	results = fetch.(tasks)
	@info "All batch jobs completed"
	
	# Disconnect from server
	RPCClient.disconnect()
	@info "Disconnected from server"
end

# Main
begin
	# Start the server
	@info "Starting server..."
	start_data_server()
	
	# Run the client
	@info "Running client..."
	run_client()
	
	# Stop the server
	@info "Stopping server..."
	RPCServer.stop_server()
	
	@info "Example completed successfully"
end 