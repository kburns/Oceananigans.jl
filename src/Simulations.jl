module Simulations

export Simulation, run!

import Base: show

using OrderedCollections: OrderedDict
using Oceananigans: AbstractDiagnostic, AbstractOutputWriter

using Oceananigans.Models
using Oceananigans.Diagnostics
using Oceananigans.OutputWriters
using Oceananigans.TimeSteppers
using Oceananigans.Utils

mutable struct Simulation{M, Δ, C, I, T, W, R, D, O, P, F}
                 model :: M
                    Δt :: Δ
         stop_criteria :: C
        stop_iteration :: I
             stop_time :: T
       wall_time_limit :: W
              run_time :: R
           diagnostics :: D
        output_writers :: O
              progress :: P
    progress_frequency :: F
end

"""
    Simulation(model; Δt,
         stop_criteria = Function[iteration_limit_exceeded, stop_time_exceeded, wall_time_limit_exceeded],
        stop_iteration = Inf,
             stop_time = Inf,
       wall_time_limit = Inf,
           diagnostics = OrderedDict{Symbol, AbstractDiagnostic}(),
        output_writers = OrderedDict{Symbol, AbstractOutputWriter}(),
              progress = nothing,
    progress_frequency = 1)

Construct an Oceananigans.jl `Simulation` for a `model` with time step `Δt`.

Keyword arguments
=================
- `Δt`: Required keyword argument specifying the simulation time step. Can be a `Number`
  for constant time steps or a `TimeStepWizard` for adaptive time-stepping.
- `stop_criteria`: A list of functions (each taking a single argument, the `simulation`).
  If any of the functions return `true` when the stop criteria is evaluated the simulation
  will stop.
- `stop_iteration`: Stop the simulation after this many iterations.
- `stop_time`: Stop the simulation once this much model clock time has passed.
- `wall_time_limit`: Stop the simulation if it's been running for longer than this many
   seconds of wall clock time.
- `progress`: A function with a single argument, the `simulation`. Will be called every
  `progress_frequency` iterations. Useful for logging simulation health.
- `progress_frequency`: How often to update the time step, check stop criteria, and call
  `progress` function (in number of iterations).
"""
function Simulation(model; Δt,
        stop_criteria = Function[iteration_limit_exceeded, stop_time_exceeded, wall_time_limit_exceeded],
       stop_iteration = Inf,
            stop_time = Inf,
      wall_time_limit = Inf,
          diagnostics = OrderedDict{Symbol, AbstractDiagnostic}(),
       output_writers = OrderedDict{Symbol, AbstractOutputWriter}(),
             progress = nothing,
   progress_frequency = 1)

   if stop_iteration == Inf && stop_time == Inf && wall_time_limit == Inf
         @warn "This simulation will run forever as stop iteration = stop time " *
               "= wall time limit = Inf."
   end

   run_time = 0.0

   return Simulation(model, Δt, stop_criteria, stop_iteration, stop_time, wall_time_limit,
                     run_time, diagnostics, output_writers, progress, progress_frequency)
end

function stop(sim)
    time_before = time()

    for sc in sim.stop_criteria
        if sc(sim)
            time_after = time()
            sim.run_time += time_after - time_before
            return true
        end
    end

    time_after = time()
    sim.run_time += time_after - time_before

    return false
end

function iteration_limit_exceeded(sim)
    if sim.model.clock.iteration >= sim.stop_iteration
          @warn "Simulation is stopping. Model iteration $(sim.model.clock.iteration) " *
                "has exceeded simulation stop iteration $(sim.stop_iteration)."
          return true
    end
    return false
end

function stop_time_exceeded(sim)
    if sim.model.clock.time >= sim.stop_time
          @warn "Simulation is stopping. Model time $(sim.model.clock.time) " *
                "has exceeded simulation stop time $(sim.stop_time)."
          return true
    end
    return false
end

function wall_time_limit_exceeded(sim)
    if sim.run_time >= sim.wall_time_limit
          @warn "Simulation is stopping. Simulation run time $(sim.run_time) " *
                "has exceeded simulation wall time limit $(sim.wall_time_limit)."
          return true
    end
    return false
end

get_Δt(Δt) = Δt
get_Δt(wizard::TimeStepWizard) = wizard.Δt

"""
    run!(simulation)

Run a `simulation` until one of the stop criteria evaluates to true and the
simulation stops.
"""
function run!(sim)
    model = sim.model
    clock = model.clock

    while !stop(sim)
        time_before = time()

        if clock.iteration == 0
            [run_diagnostic(sim.model, diag) for diag in values(sim.diagnostics)]
            [write_output(sim.model, out)    for out  in values(sim.output_writers)]
        end

        for n in 1:sim.progress_frequency
            euler = clock.iteration == 0 || (sim.Δt isa TimeStepWizard && n == 1)
            time_step!(model, get_Δt(sim.Δt), euler=euler)

            [time_to_run(clock, diag) && run_diagnostic(sim.model, diag) for diag in values(sim.diagnostics)]
            [time_to_run(clock, out)  && write_output(sim.model, out)    for out  in values(sim.output_writers)]
        end

        sim.progress isa Function && sim.progress(sim)
        sim.Δt isa TimeStepWizard && update_Δt!(sim.Δt, model)

        time_after = time()
        sim.run_time += time_after - time_before
    end

    return nothing
end

Base.show(io::IO, s::Simulation) =
    print(io, "Oceananigans.Simulation with a model on a $(typeof(s.model.architecture)) architecture \n",
            "├── Model clock: time = $(prettytime(s.model.clock.time)), iteration = $(s.model.clock.iteration) \n",
            "├── Next time step ($(typeof(s.Δt))): $(prettytime(get_Δt(s.Δt))) \n",
            "├── Progress frequency: $(s.progress_frequency)\n",
            "├── Stop criteria: $(s.stop_criteria)\n",
            "├── Run time: $(prettytime(s.run_time)), wall time limit: $(s.wall_time_limit)\n",
            "├── Stop time: $(prettytime(s.stop_time)), stop iteration: $(s.stop_iteration)\n",
            "├── Diagnostics: $(ordered_dict_show(s.model.diagnostics, " "))\n",
            "└── Output writers: $(ordered_dict_show(s.model.output_writers, "│"))\n")

end
