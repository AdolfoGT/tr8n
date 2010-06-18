class Tr8n::LanguageFilter < Tr8n::BaseFilter

  def initialize(identity)
    super('Tr8n::Language', identity)
  end

  def default_order
    'english_name'
  end
  
  def default_order_type
    'asc'
  end

  def predefined_filters(profile)
    super(profile) + [
      ["Enabled Languages", "enabled"],
      ["Disabled Languages", "disabled"],
      ["Left-to-Right Languages", "left"],
      ["Right-to-Left Languages", "right"]
    ]
  end

  def self.load_predefined_filter(profile, filter_name)
    filter = super(profile, filter_name)

    case filter_name
      when "enabled"
        filter.add_condition(:enabled, :is, '1')
      when "disabled"
        filter.add_condition(:enabled, :is, '0')
      when "left"
        filter.add_condition(:right_to_left, :is, '0')
      when "right"
        filter.add_condition(:right_to_left, :is, '1')
    end

    filter.empty? ? nil : filter
  end

end
