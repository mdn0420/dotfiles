return {
  {
    'stevearc/oil.nvim',
    opts = { view_options = { show_hidden = true } },
    keys = { { '<leader>e', '<cmd>Oil<cr>', desc = 'File Browser' } },
  },
  {
    'folke/snacks.nvim',
    priority = 1000,
    lazy = false,
    opts = {
      picker = {
        enabled = true,
        layout = {
          layout = {
            box = 'horizontal',
            width = 0,
            height = 0,
            backdrop = false,
            {
              box = 'vertical',
              border = true,
              title = '{title} {live} {flags}',
              { win = 'input', height = 1, border = 'bottom' },
              { win = 'list', border = 'none' },
            },
            { win = 'preview', title = '{preview}', border = true, width = 0.7 },
          },
        },
        sources = {
          files = { hidden = true },
          grep = { hidden = true },
          explorer = { hidden = true },
        },
      },
      notifier = { enabled = true },
      input = { enabled = true },
    },
    keys = {
      { '<leader>f', function() Snacks.picker.files() end, desc = 'Find Files' },
      { '<leader>s', function() Snacks.picker.grep() end,  desc = 'Search Text' },
      { '<leader>b', function() Snacks.picker.buffers() end, desc = 'Buffers' },
      { 'gd', function() Snacks.picker.lsp_definitions() end, desc = 'Goto Definition' },
    },
  },
}
