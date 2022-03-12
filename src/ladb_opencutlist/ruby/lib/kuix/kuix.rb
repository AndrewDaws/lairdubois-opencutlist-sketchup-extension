module Ladb::OpenCutList

  module Kuix

    require_relative 'gl/graphics'

    require_relative 'layout/border_layout'
    require_relative 'layout/static_layout'
    require_relative 'layout/grid_layout'

    require_relative 'model/size'
    require_relative 'model/point'
    require_relative 'model/metrics'
    require_relative 'model/inset'
    require_relative 'model/gap'

    require_relative 'widget/widget'
    require_relative 'widget/canvas'
    require_relative 'widget/label'

    class KuixEngine

      attr_reader :canvas

      def initialize(view)
        @canvas = Canvas.new(view)
      end

      # -- Render --

      def draw(view)

        # Check if viewport has changed
        if view.vpwidth != @canvas.width || view.vpheight != @canvas.height
          @canvas.width = view.vpwidth
          @canvas.height = view.vpheight
          @canvas.do_layout
        end

        # Check if canvas need to be revelidated
        if @canvas.is_invalidated?
          @canvas.do_layout
        end

        # Paint the canvas
        @canvas.paint(Graphics.new(view))

      end

    end

  end

end