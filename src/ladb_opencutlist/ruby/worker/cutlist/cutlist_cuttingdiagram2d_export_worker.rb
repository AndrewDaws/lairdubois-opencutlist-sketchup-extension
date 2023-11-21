module Ladb::OpenCutList

  require_relative '../../constants'
  require_relative '../../helper/sanitizer_helper'
  require_relative '../../helper/dxf_writer_helper'
  require_relative '../../helper/svg_writer_helper'
  require_relative '../../helper/pixel_converter_helper'
  require_relative '../../utils/color_utils'

  class CutlistCuttingdiagram2dExportWorker

    include SanitizerHelper
    include DxfWriterHelper
    include SvgWriterHelper
    include PixelConverterHelper

    LAYER_SHEET = 'OCL_SHEET'.freeze
    LAYER_PARTS = 'OCL_PARTS'.freeze
    LAYER_LEFTOVERS = 'OCL_LEFTOVERS'.freeze
    LAYER_CUTS = 'OCL_CUTS'.freeze

    SUPPORTED_FILE_FORMATS = [ FILE_FORMAT_SVG, FILE_FORMAT_DXF ]

    def initialize(settings, cutlist, cuttingdiagram2d)

      @file_format = settings.fetch('file_format', nil)
      @smoothing = settings.fetch('smoothing', false)
      @sheet_hidden = settings.fetch('sheet_hidden', false)
      @sheet_stroke_color = settings.fetch('sheet_stroke_color', nil)
      @sheet_fill_color = settings.fetch('sheet_fill_color', nil)
      @parts_hidden = settings.fetch('parts_hidden', false)
      @parts_stroke_color = settings.fetch('parts_stroke_color', nil)
      @parts_fill_color = settings.fetch('parts_fill_color', nil)
      @leftovers_hidden = settings.fetch('leftovers_hidden', true)
      @leftovers_stroke_color = settings.fetch('leftovers_stroke_color', nil)
      @leftovers_fill_color = settings.fetch('leftovers_fill_color', nil)
      @cuts_hidden = settings.fetch('cuts_hidden', true)
      @cuts_stroke_color = settings.fetch('cuts_stroke_color', nil)
      @hidden_sheet_indices = settings.fetch('hidden_sheet_indices', [])
      @use_names = settings.fetch('use_names', false)

      @cutlist = cutlist
      @cuttingdiagram2d = cuttingdiagram2d

    end

    # -----

    def run
      return { :errors => [ 'default.error' ] } unless @cutlist
      return { :errors => [ 'tab.cutlist.error.obsolete_cutlist' ] } if @cutlist.obsolete?
      return { :errors => [ 'default.error' ] } unless @cuttingdiagram2d && @cuttingdiagram2d.def.group
      return { :errors => [ 'default.error' ] } unless SUPPORTED_FILE_FORMATS.include?(@file_format)

      # Ask for output dir
      dir = UI.select_directory(title: Plugin.instance.get_i18n_string('tab.cutlist.cuttingdiagram.export.title'), directory: '')
      if dir

        group = @cuttingdiagram2d.def.group
        folder = _sanitize_filename("#{group.material_display_name} - #{group.std_dimension}")
        export_path = File.join(dir, folder)

        if File.exists?(export_path)
          if UI.messagebox(Plugin.instance.get_i18n_string('core.messagebox.dir_override', { :target => folder, :parent => File.basename(dir) }), MB_YESNO) == IDYES
            FileUtils.remove_dir(export_path, true)
          else
            return { :cancelled => true }
          end
        end
        Dir.mkdir(export_path)

        sheet_index = 1
        @cuttingdiagram2d.sheets.each do |sheet|
          next if @hidden_sheet_indices.include?(sheet_index)
          _write_to_path(export_path, sheet, sheet_index)
          sheet_index += sheet.count
        end

        return {
          :export_path => export_path
        }
      end

      {
        :cancelled => true
      }
    end

    # -----

    private

    def _write_to_path(export_path, sheet, sheet_index)

      # Open output file
      file = File.new(File.join(export_path, "sheet_#{sheet_index.to_s.rjust(3, '0')}#{sheet.count > 1 ? "_to_#{(sheet_index + sheet.count - 1).to_s.rjust(3, '0')}" : ''}.#{@file_format}") , 'w')

      case @file_format
      when FILE_FORMAT_SVG
        _write_to_svg_file(file, sheet)
      when FILE_FORMAT_DXF
        _write_to_dxf_file(file, sheet)
      end

      # Close output file
      file.close

    end

    def _write_to_svg_file(file, sheet)

      unit_sign, unit_transformation = _svg_get_unit_sign_and_transformation(DimensionUtils.instance.length_unit)

      size = Geom::Point3d.new(
        _to_inch(sheet.px_length),
        _to_inch(sheet.px_width)
      ).transform(unit_transformation)

      width = _svg_value(size.x)
      height = _svg_value(size.y)

      _svg_write_start(file, 0, 0, width, height, unit_sign)

      unless @sheet_hidden

        id = "#{sheet.length} x #{sheet.width}"

        _svg_write_group_start(file, id: LAYER_SHEET)
        _svg_write_tag(file, 'rect', {
          x: 0,
          y: 0,
          width: width,
          height: height,
          stroke: _svg_stroke_color(@sheet_stroke_color, @sheet_fill_color),
          fill: _svg_fill_color(@sheet_fill_color),
          id: _svg_sanitize_id(id),
          'serif:id': id
        })
        _svg_write_group_end(file)

      end

      unless @parts_hidden
        _svg_write_group_start(file, id: LAYER_PARTS)
        sheet.parts.each do |part|

          id = @use_names ? part.name : part.number

          projection_def = @cuttingdiagram2d.def.projection_defs[part.id]
          if projection_def.nil?

            position = Geom::Point3d.new(
              _to_inch(part.px_x),
              _to_inch(part.px_y)
            ).transform(unit_transformation)
            size = Geom::Point3d.new(
              _to_inch(part.px_length),
              _to_inch(part.px_width)
            ).transform(unit_transformation)

            _svg_write_tag(file, 'rect', {
              x: _svg_value(position.x),
              y: _svg_value(position.y),
              width: _svg_value(size.x),
              height: _svg_value(size.y),
              stroke: _svg_stroke_color(@parts_stroke_color, @parts_fill_color),
              fill: _svg_fill_color(@parts_fill_color),
              id: _svg_sanitize_id(id),
              'serif:id': id
            })

          else

            part_x = _to_inch(part.px_x)
            part_y = _to_inch(-part.px_y - part.px_width)
            part_x_offset = _to_inch(part.px_x_offset)
            part_y_offset = _to_inch(part.px_y_offset)
            part_length = _to_inch(part.px_length)

            transformation = unit_transformation
            if part.rotated
              transformation *= Geom::Transformation.translation(Geom::Vector3d.new(part_x + part_length - part_x_offset, part_y + part_y_offset))
              transformation *= Geom::Transformation.rotation(ORIGIN, Z_AXIS , 90.degrees)
            else
              transformation *= Geom::Transformation.translation(Geom::Vector3d.new(part_x + part_x_offset, part_y + part_y_offset))
            end

            _svg_write_group_start(file, {
              id: _svg_sanitize_id(id),
              'serif:id': id
            })

            _svg_write_projection_def(file, projection_def, @smoothing, transformation, unit_transformation, unit_sign, @parts_stroke_color, @parts_fill_color)

            _svg_write_group_end(file)

          end

        end
        _svg_write_group_end(file)
      end

      unless @leftovers_hidden
        _svg_write_group_start(file, id: LAYER_LEFTOVERS)
        sheet.leftovers.each do |leftover|

          id = "#{leftover.length} x #{leftover.width}"

          position = Geom::Point3d.new(
            _to_inch(leftover.px_x),
            _to_inch(leftover.px_y)
          ).transform(unit_transformation)
          size = Geom::Point3d.new(
            _to_inch(leftover.px_length),
            _to_inch(leftover.px_width)
          ).transform(unit_transformation)


          _svg_write_tag(file, 'rect', {
            x: _svg_value(position.x),
            y: _svg_value(position.y),
            width: _svg_value(size.x),
            height: _svg_value(size.y),
            stroke: _svg_stroke_color(@leftovers_stroke_color, @leftovers_fill_color),
            fill: _svg_fill_color(@leftovers_fill_color),
            id: _svg_sanitize_id(id),
            'serif:id': id
          })

        end
        _svg_write_group_end(file)
      end

      unless @cuts_hidden
        _svg_write_group_start(file, id: LAYER_CUTS)
        sheet.cuts.each do |cut|

          position1 = Geom::Point3d.new(
            _to_inch(cut.px_x),
            _to_inch(cut.px_y)
          ).transform(unit_transformation)
          position2 = Geom::Point3d.new(
            _to_inch(cut.px_x + (cut.is_horizontal ? cut.px_length : 0)),
            _to_inch(cut.px_y + (!cut.is_horizontal ? cut.px_length : 0))
          ).transform(unit_transformation)

          if cut.is_horizontal
            id = "y = #{cut.y}"
          else
            id = "x = #{cut.x}"
          end

          _svg_write_tag(file, 'line', {
            x1: _svg_value(position1.x),
            y1: _svg_value(position1.y),
            x2: _svg_value(position2.x),
            y2: _svg_value(position2.y),
            stroke: _svg_stroke_color(@cuts_stroke_color),
            id: _svg_sanitize_id(id),
            'serif:id': id
          })

        end
        _svg_write_group_end(file)
      end

      _svg_write_end(file)

    end

    def _write_to_dxf_file(file, sheet)

      unit_transformation = _dxf_get_unit_transformation(DimensionUtils.instance.length_unit)

      sheet_size = Geom::Point3d.new(
        _to_inch(sheet.px_length),
        _to_inch(sheet.px_width)
      ).transform(unit_transformation)

      sheet_width = sheet_size.x.to_f
      sheet_height = sheet_size.y.to_f

      layer_defs = []
      layer_defs.push({ :name => LAYER_SHEET, :color => 150 }) unless @sheet_hidden
      layer_defs.push({ :name => LAYER_PARTS, :color => 7 }) unless @parts_hidden
      layer_defs.push({ :name => LAYER_LEFTOVERS, :color => 8 }) unless @leftovers_hidden
      layer_defs.push({ :name => LAYER_CUTS, :color => 6 }) unless @cuts_hidden

      _dxf_write_header(file, Geom::Point3d.new, Geom::Point3d.new(sheet_width, sheet_height, 0), layer_defs)

      _dxf_write(file, 0, 'SECTION')
      _dxf_write(file, 2, 'ENTITIES')

      unless @sheet_hidden
        _dxf_write_rect(file, 0, 0, sheet_width, sheet_height, LAYER_SHEET)
      end

      unless @parts_hidden
        sheet.parts.each do |part|

          projection_def = @cuttingdiagram2d.def.projection_defs[part.id]
          if projection_def.nil?

            position = Geom::Point3d.new(
              _to_inch(part.px_x),
              _to_inch(sheet.px_width - part.px_y - part.px_width)
            ).transform(unit_transformation)
            size = Geom::Point3d.new(
              _to_inch(part.px_length),
              _to_inch(part.px_width)
            ).transform(unit_transformation)

            part_x = position.x.to_f
            part_y = position.y.to_f
            part_width = size.x.to_f
            part_height = size.y.to_f

            _dxf_write_rect(file, part_x, part_y, part_width, part_height, LAYER_PARTS)

          else

            part_x = _to_inch(part.px_x)
            part_y = _to_inch(sheet.px_width - part.px_y - part.px_width)
            part_x_offset = _to_inch(part.px_x_offset)
            part_y_offset = _to_inch(part.px_y_offset)
            part_width = _to_inch(part.px_length)

            transformation = unit_transformation
            if part.rotated
              transformation *= Geom::Transformation.translation(Geom::Vector3d.new(part_x + part_width - part_x_offset, part_y + part_y_offset))
              transformation *= Geom::Transformation.rotation(ORIGIN, Z_AXIS , 90.degrees)
            else
              transformation *= Geom::Transformation.translation(Geom::Vector3d.new(part_x + part_x_offset, part_y + part_y_offset))
            end

            _dxf_write_projection_def(file, projection_def, @smoothing, transformation, LAYER_PARTS)

          end
        end
      end

      unless @leftovers_hidden
        sheet.leftovers.each do |leftover|

          position = Geom::Point3d.new(
            _to_inch(leftover.px_x),
            _to_inch(sheet.px_width - leftover.px_y - leftover.px_width)
          ).transform(unit_transformation)
          size = Geom::Point3d.new(
            _to_inch(leftover.px_length),
            _to_inch(leftover.px_width)
          ).transform(unit_transformation)

          leftover_x = position.x.to_f
          leftover_y = position.y.to_f
          leftover_width = size.x.to_f
          leftover_height = size.y.to_f

          _dxf_write_rect(file, leftover_x, leftover_y, leftover_width, leftover_height, LAYER_LEFTOVERS)

        end
      end

      unless @cuts_hidden
        sheet.cuts.each do |cut|

          position1 = Geom::Point3d.new(
            _to_inch(cut.px_x),
            _to_inch(sheet.px_width - cut.px_y)
          ).transform(unit_transformation)
          position2 = Geom::Point3d.new(
            _to_inch(cut.px_x + (cut.is_horizontal ? cut.px_length : 0)),
            _to_inch(sheet.px_width - cut.px_y - (!cut.is_horizontal ? cut.px_length : 0))
          ).transform(unit_transformation)

          cut_x1 = position1.x.to_f
          cut_y1 = position1.y.to_f
          cut_x2 = position2.x.to_f
          cut_y2 = position2.y.to_f

          _dxf_write_line(file, cut_x1, cut_y1, cut_x2, cut_y2, LAYER_CUTS)

        end
      end

      _dxf_write(file, 0, 'ENDSEC')

      _dxf_write_footer(file)

    end

  end

end