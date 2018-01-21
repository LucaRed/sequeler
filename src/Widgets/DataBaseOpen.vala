/*
* Copyright (c) 2011-2017 Alecaddd (http://alecaddd.com)
*
* This program is free software; you can redistribute it and/or
* modify it under the terms of the GNU General Public
* License as published by the Free Software Foundation; either
* version 2 of the License, or (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
* General Public License for more details.
*
* You should have received a copy of the GNU General Public
* License along with this program; if not, write to the
* Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
* Boston, MA 02110-1301 USA
*
* Authored by: Alessandro "Alecaddd" Castellani <castellani.ale@gmail.com>
*/
namespace Sequeler { 
    public class DataBaseOpen : Gtk.Box {

        public Gtk.Paned main_pane;
        public Gtk.Paned pane;
        public Gtk.Stack db_stack;
        public Gtk.Box query_bar;
        public Gtk.Box sidebar;
        public Gtk.Box db_structure;
        public Gtk.Box db_content;
        public Gtk.Box db_relations;
        public Gtk.Button run_button;
        public Gtk.Spinner spinner;
        public Gtk.Label result_message;
        public Gtk.Label loading_msg;
        public Gtk.ScrolledWindow scroll_results;
        public Gtk.ScrolledWindow scroll_sidebar;
        public Gdaui.RawGrid results_view;
        public Gtk.Label error_view;
        public Gdaui.RawGrid structure_results;
        public QueryBuilder query_builder;
        public int column_pos;
        public string? selected_table { set; get; default = null; }

        public Gee.HashMap<string,string> data;

        public signal int execute_query (string query);
        public signal Gda.DataModel? execute_select (string query);

        public DataBaseOpen () {
            orientation = Gtk.Orientation.VERTICAL;

            main_pane = new Gtk.Paned (Gtk.Orientation.HORIZONTAL);
            main_pane.wide_handle = true;
            main_pane.set_position (240);

            pane = new Gtk.Paned (Gtk.Orientation.VERTICAL);
            pane.wide_handle = true;

            this.pack_start (main_pane, true, true, 0);

            build_sidebar ();

            db_structure = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            build_structure ();
            //  build_content ();
            //  build_relations ();
            build_editor ();
            build_query_bar ();
            build_treeview ();

            connect_signals ();
            handle_shortcuts ();

            db_stack = new Gtk.Stack ();
            db_stack.add_named (db_structure, "Structure");
            //  db_stack.add_named (db_content, "Content");
            //  db_stack.add_named (db_relations, "Relations");
            db_stack.add_named (pane, "Query");

            main_pane.add2 (db_stack);
        }

        public void set_database_data (Gee.HashMap<string,string> data){
            this.data = data;
        }

        public void build_sidebar () {
            sidebar = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            sidebar.width_request = 240;

            main_pane.pack1 (sidebar, true, false);
        }

        public void init_sidebar () {
            var table_query = "";

            if (data["type"] == "SQLite") {
                table_query = "SELECT name, sql FROM sqlite_master WHERE type='table' ORDER BY name;";
                sidebar_table (execute_select (table_query));
                toolbar.clear_table_schema ();
                return;
            }

            if (data["type"] == "MySQL" || data["type"] == "MariaDB") {
                table_query = "SHOW SCHEMAS";
            }

            if (data["type"] == "PostgreSQL") {
                table_query = "SELECT schema_name FROM information_schema.schemata";
            }

            toolbar.set_table_schema (execute_select (table_query));

            toolbar.schema_list_combo.changed.connect (() => {
                if (toolbar.schema_list_combo.get_active () == 0) {
                    return;
                }
                populate_sidebar_table (toolbar.schemas[toolbar.schema_list_combo.get_active ()]);
            });
        }

        public void populate_sidebar_table (string? table) {
            var table_query = "";

            if (data["type"] == "MySQL" || data["type"] == "MariaDB") {
                table_query = "SELECT table_name FROM information_schema.TABLES WHERE table_schema = '" + table + "' ORDER BY table_name DESC";
            }

            if (data["type"] == "PostgreSQL") {
                //  table_query = "SELECT * FROM information_schema.tables WHERE table_schema = '" + table + "' ORDER BY table_name DESC";
                table_query = "SELECT tablename FROM pg_catalog.pg_tables WHERE schemaname != 'information_schema' AND schemaname != 'pg_catalog' ORDER BY tablename DESC";
            }

            sidebar_table (execute_select (table_query));
        }

        public void sidebar_table (Gda.DataModel? response) {
            if (response == null) {
                return;
            }

            if (scroll_sidebar != null) {
                sidebar.remove (scroll_sidebar);
                scroll_sidebar = null;
            }

            scroll_sidebar = new Gtk.ScrolledWindow (null, null);
            scroll_sidebar.set_policy (Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);

            var source_list = new Granite.Widgets.SourceList ();
            var tables_category = new Granite.Widgets.SourceList.ExpandableItem (_("TABLES"));
            tables_category.expand_all ();

            Gda.DataModelIter _iter = response.create_iter ();
            int top = 0;
            while (_iter.move_next ()) {
                tables_category.add (new Granite.Widgets.SourceList.Item (_iter.get_value_at (0).get_string ()));      
                top++;
            }

            source_list.root.add (tables_category);
            scroll_sidebar.add (source_list);

            source_list.item_selected.connect ((item) => {
                if (item == null) {
                    return;
                }
                fill_structure (item.name);
            });

            sidebar.pack_start (scroll_sidebar, true, true, 0);

            sidebar.show_all ();
            toolbar.tabs.sensitive = true;
            toolbar.tabs.set_active (0);
        }

        public void build_editor () {
            var scroll = new Gtk.ScrolledWindow (null, null);
            scroll.set_policy (Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);

            query_builder = new QueryBuilder ();
            query_builder.update_run_button.connect ((status) => {
                run_button.sensitive = status;
            });

            scroll.add (query_builder);

            var editor = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            editor.height_request = 100;

            editor.pack_start (scroll, true, true, 0);

            pane.pack1 (editor, true, false);
        }

        public void build_query_bar () {
            query_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            query_bar.get_style_context ().add_class ("query_bar");
            query_bar.get_style_context ().add_class ("library-query_bar");

            var run_image = new Gtk.Image.from_icon_name ("system-run-symbolic", Gtk.IconSize.BUTTON);
            run_button = new Gtk.Button.with_label (_("Run Query"));
            run_button.get_style_context ().add_class ("suggested-action");
            run_button.always_show_image = true;
            run_button.set_image (run_image);
            run_button.can_focus = false;
            run_button.margin = 10;
            run_button.sensitive = false;

            spinner = new Gtk.Spinner ();

            loading_msg = new Gtk.Label (_("Running Query..."));
            loading_msg.visible = false;
            loading_msg.no_show_all = true;

            result_message = new Gtk.Label (_("No Results Available"));
            result_message.visible = false;
            result_message.no_show_all = true;

            query_bar.pack_start (loading_msg, false, false, 10);
            query_bar.pack_start (result_message, false, false, 10);
            query_bar.pack_start (spinner, false, false, 10);
            query_bar.pack_end (run_button, false, false, 0);
        }

        public void build_treeview () {
            var results = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            results.height_request = 100;

            results.add (query_bar);

            scroll_results = new Gtk.ScrolledWindow (null, null);
            scroll_results.set_policy (Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);

            results.pack_start (scroll_results, true, true, 0);

            pane.pack2 (results, true, false);
        }

        public void reload_data (string tab) {
            switch (tab) {
                case "Structure":
                    fill_structure (toolbar.selected_table);
                    break;
                case "Content":
                    break;
                case "Relations":
                    break;
                case "Query":
                    break;
            }
        }

        public void build_structure () {
            var structure_intro = new Granite.Widgets.Welcome (_("Select Table"), _("Select a table from the left sidebar to activate this view."));
            db_structure.add (structure_intro);
            db_structure.show_all ();
        }

        public void fill_structure (string? table) {
            if (table == selected_table || table == null) {
                return;
            }

            if (db_structure != null) {
                db_structure.forall ((element) => db_structure.remove (element));
            }

            selected_table = table;
            toolbar.selected_table = table;

            var structure_scroll = new Gtk.ScrolledWindow (null, null);
            structure_scroll.set_policy (Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
            db_structure.pack_start (structure_scroll, true, true, 0);

            //  structure_results = new Sequeler.TreeBuilder (structure_query (selected_table));
            structure_results = new Gdaui.RawGrid (structure_query (selected_table));
            //  structure_results.enable_grid_lines = Gtk.TreeViewGridLines.HORIZONTAL;
            structure_results.rules_hint = true;
            structure_results.show_expanders = true;
            structure_results.rubber_banding = true;
            structure_results.headers_visible = true;
            structure_results.enable_search = true;
            structure_results.columns_autosize ();
            foreach (var column in structure_results.get_columns ()) {
                column.sort_indicator = true;
                column.resizable = true;
                column.clickable = true;
            }
            structure_scroll.add (structure_results);

            db_structure.show_all ();
        }

        public Gda.DataModel? structure_query(string table) {
            var table_query = "";

            if (data["type"] == "SQLite") {
                table_query = "PRAGMA table_info('" + table + "');";
            }

            if (data["type"] == "MySQL" || data["type"] == "MariaDB") {
                table_query = "SELECT * FROM information_schema.COLUMNS WHERE table_name='" + table + "' AND table_schema = '" + data["name"] + "';";
            }

            if (data["type"] == "PostgreSQL") {
                table_query = "SELECT * FROM information_schema.COLUMNS WHERE table_name='" + table + "';";
            }

            return execute_select (table_query);
        }

        //  public void build_content () {
        //      db_content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        //      db_content.add (new Gtk.Label ("Content"));
        //  }

        //  public void build_relations () {
        //      db_relations = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        //      db_relations.add (new Gtk.Label ("Relations"));
        //  }

        public void connect_signals () {
            run_button.clicked.connect (() => {
                init_query ();
            });
        }

        private void handle_shortcuts () {
            query_builder.key_press_event.connect ( (e) => {
                bool handled = false;
                if((e.state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    switch (e.keyval) {
                        case 65293:
                            init_query ();
                            handled = true;
                            break;
                        default:
                            break;
                    }
                }

                return handled;
            });
        }

        public void init_query () {
            show_loading ();
            
            if (results_view != null) {
                scroll_results.remove (results_view);
                results_view = null;
            }

            if (error_view != null) {
                query_bar.remove (error_view);
                error_view = null;
            }

            var query = query_builder.get_text ();

            if ("select" in query.down ()) {
                handle_select_response (execute_select (query));
            } else {
                handle_query_response (execute_query (query));
            }
        }

        public void handle_query_response (int response) {
            hide_loading ();

            if (response == 0) {
                result_message.label = _("Unable to process Query!");
            } else if (response < 0) {
                result_message.label = _("Query Executed!");
            } else {
                result_message.label = _("Query Successfully Executed! Rows affected: ") + response.to_string ();
            }

            if (response != 0) {
                init_sidebar ();
            }
        }

        public void handle_select_response (Gda.DataModel? response) {
            hide_loading ();

            if (response == null) {
                result_message.label = _("Unable to process Query!");
                return;
            }
            
            //  results_view = new Sequeler.TreeBuilder (response);
            results_view = new Gdaui.RawGrid (response);
            //  results_view.enable_grid_lines = Gtk.TreeViewGridLines.HORIZONTAL;
            results_view.rules_hint = true;
            results_view.show_expanders = true;
            results_view.columns_autosize ();
            scroll_results.add (results_view);

            scroll_results.show_all ();

            result_message.label = _("Query Successfully Executed!");
        }

        public void render_query_error (string error) {
            error_view = new Gtk.Label (error);

            query_bar.add (error_view);
            query_bar.show_all ();
        }

        public void hide_loading () {
            spinner.stop ();
            loading_msg.visible = false;
            loading_msg.no_show_all = true;

            result_message.visible = true;
            result_message.no_show_all = false;
        }

        public void show_loading () {
            spinner.start ();
            loading_msg.visible = true;
            loading_msg.no_show_all = false;

            result_message.visible = false;
            result_message.no_show_all = true;
        }

        public void clear_results () {
            if (results_view != null) {
                scroll_results.remove (results_view);
                results_view = null;
            }
            if (error_view != null) {
                query_bar.remove (error_view);
                error_view = null;
            }
            if (db_structure != null) {
                db_structure.forall ((element) => db_structure.remove (element));
                build_structure ();
            }
            if (scroll_sidebar != null) {
                sidebar.remove (scroll_sidebar);
                scroll_sidebar = null;
            }
        }
    }
}