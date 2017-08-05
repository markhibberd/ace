var preset = world.sites.reduce(function(acc, o) {
  return acc && o.x !== undefined && o.y !== undefined;
}, true);

var mines = world.mines.reduce(function(acc, n) {
  acc[n] = true;
  return acc;
}, {});

var sites = world.sites.map(function(o) {
  var node = {
    "data": {
      "id": o.id,
      "mine": mines[o.id] === true
    },
    "position": {
      "x": o.x === undefined ? 0 : o.x,
      "y": o.y === undefined ? 0 : o.y
    }
  };

  return node;
});

var calculateRivers = function(moves) {
  var moves2 = moves.reduce(function(acc, s, i) {
    if (s.claim !== undefined) {
      var c = s.claim;
      var id = c.source + ":" + c.target;
      acc[id] = {};
      acc[id].punter = c.punter;
      acc[id].move = i;
    }
    return acc;
  }, {});

  var punters = moves.reduce(function(acc, s) {
    if (s.claim !== undefined) {
      var c = s.claim;
      acc[c.punter] = acc[c.punter] !== undefined ? acc[c.punter] + 1 : 0;
    }
    return acc;
  }, {});

  var punterCount = Object.keys(punters).length;

  return world.rivers.map(function(o) {
    var id = o.source.toString() + ":" + o.target.toString();
    var edge = {
      "data": {
        "id": id,
        "source": o.source,
        "target": o.target,
        "punter": moves2[id] ? moves2[id].punter : undefined,
        "move": moves2[id] ? moves2[id].move : undefined
      }
    };

    return edge;
  });
};
var moves = window.moves || [];
var rivers = calculateRivers(moves);

var colours = [];
colours[0] = 'aqua';
colours[1] = 'blue';
colours[2] = 'fuchsia';
colours[3] = 'gray';
colours[4] = 'lime';
colours[5] = 'maroon';
colours[6] = 'navy';
colours[7] = 'olive';
colours[8] = 'purple';
colours[9] = 'yellow';
colours[10] = 'silver';
colours[11] = 'teal';

if (window.player !== undefined) {
  colours[window.player] = 'red';
}

window.onload = function() {
  var cy = cytoscape({
    container: document.getElementById('world'), // container to render in
    elements: sites.concat(rivers),

    style: [ // the stylesheet for the graph
      {
        selector: 'node',
        style: {
          'label': 'data(id)',
          'background-color': function(o) {
            return o.data('mine') ? "#de4526" : '#288119';
          }
        }
      },

      {
        selector: 'edge',
        style: {
          'width': 3,
          'line-color': function(o) {
            var punter = o.data('punter')
            var move = o.data('move')
            return (punter !== null && move < moveG ? colours[punter % colours.length] : 'black');
          }
        }
      }
    ],

    layout: {
      name: preset ? 'preset' : 'cose'
    }
  });
  var elMove = document.querySelector('#move');
  var elTotal = document.querySelector('#total');
  var elNext = document.querySelector('#next');
  var elPrev = document.querySelector('#prev');
  var moveG = moves.length;
  var refresh = function(move) {
    var moveG2 = Math.max(0, Math.min(moves.length, move));
    if (moveG !== moveG2) {
      elMove.value = moveG2.toString();
      moveG = moveG2;
    }
    elTotal.innerHTML = moves.length.toString();
    cy.json({elements: sites.concat(rivers)});
  };
  elMove.onkeydown = function(e) {
    if (e.keyCode === 13) {
      refresh(parseInt(elMove.value));
    }
  };
  elNext.onclick = function() {
    refresh(moveG + 1);
  };
  elPrev.onclick = function() {
    refresh(moveG - 1);
  };
  refresh(moveG);

  var loop = function() {
    var xhttp = new XMLHttpRequest();
    xhttp.onreadystatechange = function() {
      if (this.readyState === 4 && this.status === 200) {
        moves = [].concat.apply([], this.responseText.split('\n')
          .filter(function(x) { return x !== '' })
          .map(function(j) { return JSON.parse(j); })
          );
        rivers = calculateRivers(moves);
        refresh(moveG);
      }
    };
    xhttp.open("GET", "moves.txt", true);
    xhttp.send();
    setTimeout(loop, 1000);
  };
  loop();
};
