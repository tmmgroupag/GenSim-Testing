# frozen_string_literal: true

require_relative "resources/manual_ventilation_output"

# start the measure
class InjectManualVentilationIDF < OpenStudio::Measure::EnergyPlusMeasure
  include ManualVentilationOutput
  # human readable name
  def name
    return "InjectManualVentilationIDF"
  end

  # general description of measure
  def description
    return "Inject manual window ventilation and report its estimated sensible heat loss and gain."
  end

  # description for users of what the measure does and how it works
  def modeler_description
    return "Adds passive EMS diagnostics using the manual schedule, zone volume, local weather and BLAST/DOE2 coefficients. Reports estimated sensible heat loss and gain without changing the simulated ventilation."
  end

  # define the arguments that the user will input
  def arguments(_workspace)
    args = OpenStudio::Measure::OSArgumentVector.new

    args << OpenStudio::Measure::OSArgument.makeDoubleArgument("air_changes", true)

    dtsS = OpenStudio::Measure::OSArgument.makeStringArgument("infiltration_type", false)
    dtsS.setDefaultValue("BLAST")
    args << dtsS

    return args
  end

  # define what happens when the measure is run
  def run(workspace, runner, user_arguments)
    super(workspace, runner, user_arguments)

    # use the built-in error checking
    return false unless runner.validateUserArguments(arguments(workspace), user_arguments)

    # assign the user inputs to variables
    ventilationACH = runner.getDoubleArgumentValue("air_changes", user_arguments)
    infiltration_type = runner.getStringArgumentValue("infiltration_type", user_arguments)

    if ventilationACH < 0
      runner.registerError("Manual ventilation air_changes must be non-negative.")
      return false
    end

    if workspace.getObjectsByType("EnergyManagementSystem:Program".to_IddObjectType).any? { |program| program.nameString == "ManualVentilationHeatOutput" }
      runner.registerError("Manual ventilation is already defined. Use one schedule with multiple ventilation periods.")
      return false
    end

    # get all thermal zones in the starting model
    zones = workspace.getObjectsByType("Zone".to_IddObjectType)

    # reporting initial condition of model
    runner.registerInitialCondition("The building started with #{zones.size} zones.")

    # first we built a list of perimeter zones
    perimeterZones = []
    bPerimeterZonesFound = false
    zones.each do |zone|
      if zone.name.to_s.include? "Perimeter"
        perimeterZones << zone
        bPerimeterZonesFound = true
      end
    end

    unless bPerimeterZonesFound
      zones.each do |zone|
        if zone.name.to_s.include? "EXT-"
          perimeterZones << zone
          bPerimeterZonesFound = true
        end
      end
    end

    runner.registerInfo("We found #{perimeterZones.size} perimeter zones")
    unless bPerimeterZonesFound
      perimeterZones = zones
      runner.registerInfo("Using all zones since we did not find any perimeter zones.")
    end

    perimeterZones.each do |zone|
      zoneVent = OpenStudio::IdfObject.new("ZoneVentilation:DesignFlowRate".to_IddObjectType)
      zoneVent.setString(0, "#{zone.name} - Manual Ventilation")
      zoneVent.setString(1, zone.name.to_s)
      zoneVent.setString(2, "ManualVentilationSchedule")
      zoneVent.setString(3, "AirChanges/Hour")
      zoneVent.setDouble(7, ventilationACH)
      zoneVent.setString(8, "Natural")
      if infiltration_type == "BLAST"
          zoneVent.setDouble(11, 0.606)
          zoneVent.setDouble(12, 0.03636)
          zoneVent.setDouble(13, 0.1177)
          zoneVent.setDouble(14, 0)
      elsif infiltration_type == "DOE2"
          zoneVent.setDouble(11, 0)
          zoneVent.setDouble(12, 0)
          zoneVent.setDouble(13, 0.224)
          zoneVent.setDouble(14, 0)
      else
          zoneVent.setDouble(11, 1)
          zoneVent.setDouble(12, 0)
          zoneVent.setDouble(13, 0)
          zoneVent.setDouble(14, 0)
      end
      zoneVent.setDouble(15, -100)
      zoneVent.setDouble(19, -100)
      workspace.addObject(zoneVent)
    end

    unless perimeterZones.empty?
      add_manual_ventilation_output(workspace, perimeterZones, ventilationACH, infiltration_type)
      runner.registerInfo("Added estimated manual ventilation sensible heat loss/gain. These diagnostic outputs do not change ventilation or represent additional HVAC demand.")
    end

    # report final condition of model
    zoneVentilation = workspace.getObjectsByType("ZoneVentilation:DesignFlowRate".to_IddObjectType)
    runner.registerFinalCondition("The building finished with #{zoneVentilation.size} Manual ZoneVentilation objects.")

    return true
  end
end

# register the measure to be used by the application
InjectManualVentilationIDF.new.registerWithApplication
