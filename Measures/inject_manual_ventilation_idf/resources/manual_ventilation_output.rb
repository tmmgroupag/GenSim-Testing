# frozen_string_literal: true

# Diagnostic heat-flow estimate for the natural ventilation objects created by
# this measure. No actuators are used: the simulated airflows are not changed.
module ManualVentilationOutput
  def add_manual_ventilation_output(workspace, zones, air_changes, infiltration_type)
    add_ems_object(workspace, "Sensor", ["MV_Schedule", "ManualVentilationSchedule", "Schedule Value"])
    add_ems_object(workspace, "Sensor", ["MV_Pressure", "Environment", "Site Outdoor Air Barometric Pressure"])
    add_ems_object(workspace, "Sensor", ["MV_Humidity", "Environment", "Site Outdoor Air Humidity Ratio"])

    coefficients = case infiltration_type
                   when "BLAST" then [0.606, 0.03636, 0.1177]
                   when "DOE2" then [0.0, 0.0, 0.224]
                   else [1.0, 0.0, 0.0]
                   end
    constant, temperature, wind = coefficients
    lines = ["SET MV_Loss = 0", "SET MV_Gain = 0"]

    zones.each_with_index do |zone, index|
      prefix = "MV_Z#{index + 1}"
      {
        "Indoor" => "Zone Mean Air Temperature",
        "Outdoor" => "Zone Outdoor Air Drybulb Temperature",
        "Wind" => "Zone Outdoor Air Wind Speed"
      }.each do |suffix, variable|
        add_ems_object(workspace, "Sensor", ["#{prefix}_#{suffix}", zone.nameString, variable])
      end
      add_ems_object(workspace, "InternalVariable", ["#{prefix}_Volume", zone.nameString, "Zone Air Volume"])

      # These limits match the defaults of our ZoneVentilation:DesignFlowRate
      # objects, including the two -100 C overrides in measure.rb.
      lines.concat([
        "SET MV_Delta = #{prefix}_Indoor - #{prefix}_Outdoor",
        "SET MV_Flow = 0",
        "IF #{prefix}_Indoor >= -100 && #{prefix}_Indoor <= 100",
        "IF #{prefix}_Outdoor >= -100 && #{prefix}_Outdoor <= 100",
        "IF MV_Delta >= -100 && #{prefix}_Wind <= 40",
        "SET MV_Correction = @Abs MV_Delta",
        "SET MV_Correction = #{constant} + #{temperature} * MV_Correction + #{wind} * #{prefix}_Wind",
        "SET MV_Flow = #{air_changes} * #{prefix}_Volume / 3600 * MV_Schedule * MV_Correction",
        "SET MV_Flow = @Max 0 MV_Flow",
        "ENDIF",
        "ENDIF",
        "ENDIF",
        "SET MV_Density = @RhoAirFnPbTdbW MV_Pressure #{prefix}_Outdoor MV_Humidity",
        "SET MV_Cp = @CpAirFnW MV_Humidity",
        "SET MV_Energy = MV_Flow * MV_Density * MV_Cp * MV_Delta * SystemTimeStep * 3600",
        "IF MV_Energy >= 0",
        "SET MV_Loss = MV_Loss + MV_Energy",
        "ELSE",
        "SET MV_Gain = MV_Gain - MV_Energy",
        "ENDIF"
      ])
    end

    program = "ManualVentilationHeatOutput"
    add_ems_object(workspace, "Program", [program, *lines])
    add_ems_object(workspace, "ProgramCallingManager", [
      "ManualVentilationHeatOutputManager", "EndOfSystemTimestepBeforeHVACReporting", program
    ])
    %w[Loss Gain].each do |direction|
      add_ems_object(workspace, "OutputVariable", [
        "Manual Ventilation Estimated Sensible Heat #{direction} Energy",
        "MV_#{direction}", "Summed", "SystemTimestep", program, "J"
      ])
    end
  end

  def add_ems_object(workspace, type, fields)
    object = OpenStudio::IdfObject.new("EnergyManagementSystem:#{type}".to_IddObjectType)
    fields.each_with_index { |value, index| object.setString(index, value) }
    workspace.addObject(object)
  end
end
