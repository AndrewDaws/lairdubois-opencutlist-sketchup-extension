+function ($) {
    'use strict';

    // CLASS DEFINITION
    // ======================

    var LadbEditorExport = function (element, options, dialog) {
        this.options = options;
        this.$element = $(element);
        this.dialog = dialog;

        this.wordDefs = [];

        this.$editingItem = null;
        this.$editingForm = null;
    };

    LadbEditorExport.DEFAULTS = {
        variables: []
    };

    LadbEditorExport.prototype.setColdefs = function (colDefs) {
        var that = this;

        // Cancel editing
        this.editColumn(null);

        // Populate rows
        this.$sortable.empty();
        $.each(colDefs, function (index, colDef) {

            // Append column
            that.appendColumn(colDef.name, colDef.header, colDef.formula, colDef.hidden);

        });

        // Bind sorter
        this.$sortable.sortable(SORTABLE_OPTIONS);

    };

    LadbEditorExport.prototype.getColdefs = function () {
        var colDefs = [];
        this.$sortable.children('li').each(function () {
            colDefs.push({
                name: $(this).data('name'),
                header: $(this).data('header'),
                formula: $(this).data('formula'),
                hidden: $(this).data('hidden')
            });
        });
        return colDefs;
    };

    LadbEditorExport.prototype.appendColumn = function (name, header, formula, hidden) {
        var that = this;

        // Create and append row
        var $item = $(Twig.twig({ref: "tabs/cutlist/_export-column-item.twig"}).render({
            name: name,
            header: header,
            formula: formula,
            hidden: hidden
        }));
        this.$sortable.append($item);

        // Bind row
        $item.on('click', function () {
            that.editColumn($item);
            return false;
        })

        // Bind buttons
        $('a.ladb-cutlist-export-column-item-formula-btn', $item).on('click', function () {
            that.editColumn($item, 'formula');
            return false;
        });
        $('a.ladb-cutlist-export-column-item-visibility-btn', $item).on('click', function () {
            var $icon = $('i', $(this));
            var hidden = $item.data('hidden');
            if (hidden === true) {
                hidden = false;
                $item.removeClass('ladb-inactive');
                $icon.removeClass('ladb-opencutlist-icon-eye-close');
                $icon.addClass('ladb-opencutlist-icon-eye-open');
            } else {
                hidden = true;
                $item.addClass('ladb-inactive');
                $icon.addClass('ladb-opencutlist-icon-eye-close');
                $icon.removeClass('ladb-opencutlist-icon-eye-open');
            }
            $item.data('hidden', hidden);
            return false;
        });

        return $item;
    };

    LadbEditorExport.prototype.editColumn = function ($item, focus) {
        var that = this;

        // Cleanup
        if (this.$editingForm) {
            this.$editingForm.remove();
        }
        if (this.$btnContainer) {
            this.$btnContainer.empty();
        }
        if (this.$editingItem) {
            this.$editingItem.removeClass('ladb-selected');
        }

        this.$editingItem = $item;
        if ($item) {

            // Mark item as selected
            this.$editingItem.addClass('ladb-selected');

            // Buttons
            var $btnRemove = $('<button class="btn btn-danger"><i class="ladb-opencutlist-icon-clear"></i> ' + i18next.t('tab.cutlist.export.remove_column') + '</button>');
            $btnRemove
                .on('click', function () {
                    that.removeColumn($item);
                })
            ;
            this.$btnContainer.append($btnRemove);

            // Create the form
            this.$editingForm = $(Twig.twig({ref: "tabs/cutlist/_export-column-form.twig"}).render({
                name: $item.data('name'),
                header: $item.data('header')
            }));

            var $inputHeader = $('#ladb_input_header', this.$editingForm);
            var $editorFormula = $('#ladb_div_formula', this.$editingForm);

            // Bind input
            $inputHeader.on('keyup', function () {
                $item.data('header', $(this).val());

                // Update item header
                $('.ladb-cutlist-export-column-item-header', $item).replaceWith(Twig.twig({ref: "tabs/cutlist/_export-column-item-header.twig"}).render({
                    name: $item.data('name'),
                    header: $item.data('header')
                }))

            });

            // Bind editor
            $editorFormula
                .ladbEditorFormula({
                    wordDefs: this.wordDefs
                })
                .ladbEditorFormula('setFormula', [$item.data('formula')])
                .on('change', function () {
                    $item.data('formula', $(this).ladbEditorFormula('getFormula'));
                })
            ;

            this.$element.append(this.$editingForm);

            // Focus
            if (focus === 'formula') {
                $editorFormula.focus();
            } else {
                $inputHeader.focus();
            }

        }

    };

    LadbEditorExport.prototype.removeColumn = function ($item) {

        // Remove column item
        $item.remove();

        // Cancel editing
        this.editColumn(null);

    };

    LadbEditorExport.prototype.addColumn = function (name) {
        var $item = this.appendColumn(name)
        this.editColumn($item);
    };

    LadbEditorExport.prototype.init = function () {
        var that = this;

        // Generate wordDefs for formula editor
        this.wordDefs = [];
        for (var i = 0; i < this.options.vars.length; i++) {
            this.wordDefs.push({
                value: this.options.vars[i],
                label: i18next.t('tab.cutlist.export.' + this.options.vars[i]),
                class: 'variable'
            });
        }

        // Build UI

        var $header = $('<div class="ladb-editor-export-header">').append(i18next.t('tab.cutlist.export.columns'))
        this.$sortable = $('<ul class="ladb-editor-export-sortable ladb-sortable-list" />')

        this.$element.append(
            $('<div class="ladb-editor-export-container">')
                .append($header)
                .append(this.$sortable)
        )

        // Buttons

        var $btnAdd = $('<button class="btn btn-default"><i class="ladb-opencutlist-icon-plus"></i> ' + i18next.t('tab.cutlist.export.add_column') + '</button>')
            .on('click', function () {
                that.addColumn('');
            });

        var $dropDown = $('<ul class="dropdown-menu dropdown-menu-right">');
        $dropDown.append(
            $('<li class="dropdown-header">' + i18next.t('tab.cutlist.export.add_native_columns') + '</li>')
        )
        $.each(this.options.vars, function (index, v) {
            $dropDown.append(
                $('<li>')
                    .append(
                        $('<a href="#">' + i18next.t('tab.cutlist.export.' + v) + '</a>')
                            .on('click', function () {
                                that.addColumn(v);
                            })
                    )
            )
        });

        var $btnGroup = $('<div class="btn-group">')
            .append($btnAdd)
            .append($('<button type="button" class="btn btn-default dropdown-toggle" data-toggle="dropdown"><span class="caret"></span></button>'))
            .append($dropDown)

        var $btnContainer = $('<div style="display: inline-block" />');

        this.$element.append(
            $('<div class="ladb-editor-export-buttons" style="margin: 10px;"></div>')
                .append($btnGroup)
                .append('&nbsp;')
                .append($btnContainer)
        );

        this.$btnContainer = $btnContainer;

    };

    // PLUGIN DEFINITION
    // =======================

    function Plugin(option, params) {
        var value;
        var elements = this.each(function () {
            var $this = $(this);
            var data = $this.data('ladb.editorExport');
            var options = $.extend({}, LadbEditorExport.DEFAULTS, $this.data(), typeof option === 'object' && option);

            if (!data) {
                $this.data('ladb.editorExport', (data = new LadbEditorExport(this, options, options.dialog)));
            }
            if (typeof option === 'string') {
                value = data[option].apply(data, Array.isArray(params) ? params : [ params ])
            } else {
                data.init(params);
            }
        });
        return typeof value !== 'undefined' ? value : elements;
    }

    var old = $.fn.ladbEditorExport;

    $.fn.ladbEditorExport = Plugin;
    $.fn.ladbEditorExport.Constructor = LadbEditorExport;


    // NO CONFLICT
    // =================

    $.fn.ladbEditorExport.noConflict = function () {
        $.fn.ladbEditorExport = old;
        return this;
    }

}(jQuery);