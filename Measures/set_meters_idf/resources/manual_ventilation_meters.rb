# frozen_string_literal: true

module ManualVentilationMeters
  # Check the final IDF here, after both ventilation measures have run.
  # Never label a partial or mixed zone balance as the total manual contribution.
  def manual_ventilation_zones(workspace, runner)
    names = %w[Loss Gain].map { |direction| "METER MANUAL VENTILATION SENSIBLE HEAT #{direction.upcase} ENERGY" }
    %w[Meter:Custom Output:Meter].each do |type|
      workspace.getObjectsByType(type.to_IddObjectType).each do |object|
        workspace.removeObject(object.handle) if names.include?(object.getString(0).to_s.upcase)
      end
    end

    ventilation = workspace.getObjectsByType("ZoneVentilation:DesignFlowRate".to_IddObjectType).to_a
    manual = ventilation.select do |object|
      object.nameString.end_with?(" - Manual Ventilation") &&
        object.getString(2).to_s.casecmp("ManualVentilationSchedule").zero?
    end
    return [] if manual.empty?

    zone_names = workspace.getObjectsByType("Zone".to_IddObjectType).map { |zone| zone.nameString.upcase }
    zones = manual.map { |object| object.getString(1).to_s.upcase }.uniq
    unless (zones - zone_names).empty?
      runner.registerWarning("Manual ventilation balance omitted: manual objects must reference individual zones.")
      return []
    end

    zone_lists = {}
    workspace.getObjectsByType("ZoneList".to_IddObjectType).each do |list|
      zone_lists[list.nameString.upcase] = (1...list.numFields).map { |index| list.getString(index).to_s.upcase }
    end

    others = ventilation - manual
    others.concat(workspace.getObjectsByType("ZoneVentilation:WindandStackOpenArea".to_IddObjectType).to_a)
    conflicts = others.select do |object|
      target = object.getString(1).to_s.upcase
      targets = zone_lists.fetch(target, [target])
      # Unknown targets (e.g. Space/SpaceList) cannot be safely attributed here.
      !(targets - zone_names).empty? || !(targets & zones).empty?
    end

    quadrature = workspace.getObjectsByType("ZoneAirBalance:OutdoorAir".to_IddObjectType).any? do |object|
      zones.include?(object.getString(1).to_s.upcase) && object.getString(2, true).to_s.casecmp("Quadrature").zero?
    end
    airflow_network = !workspace.getObjectsByType("AirflowNetwork:SimulationControl".to_IddObjectType).empty?

    if !conflicts.empty? || quadrature || airflow_network
      runner.registerWarning("Manual ventilation balance omitted: other zone ventilation, combined outdoor air balance or AirflowNetwork prevents an unambiguous manual-only balance. Conflicting objects: #{conflicts.map(&:nameString).join(', ')}")
      return []
    end

    runner.registerInfo("Direct manual ventilation balance enabled for #{zones.size} zones: #{zones.join(', ')}")
    zones
  end

  def create_manual_ventilation_meter(workspace, definition, zones)
    meter = OpenStudio::IdfObject.new("Meter:Custom".to_IddObjectType)
    meter.setString(0, "Meter " + definition["name"])
    meter.setString(1, "Generic")
    zones.each_with_index do |zone, index|
      meter.setString(2 + index * 2, zone)
      meter.setString(3 + index * 2, definition["eplus_variables"].first)
    end
    workspace.insertObject(meter)
  end
end
