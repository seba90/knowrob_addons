/** <module> knowrob_chemlab

  Copyright (C) 2013 by Asil Kaan Bozcuoglu, Moritz Tenorth, Daniel Beßler

  Redistribution and use in source and binary forms, with or without
  modification, are permitted provided that the following conditions are met:
      * Redistributions of source code must retain the above copyright
        notice, this list of conditions and the following disclaimer.
      * Redistributions in binary form must reproduce the above copyright
        notice, this list of conditions and the following disclaimer in the
        documentation and/or other materials provided with the distribution.
      * Neither the name of the <organization> nor the
        names of its contributors may be used to endorse or promote products
        derived from this software without specific prior written permission.

  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
  DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
  DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

@author Asil Kaan Bozcuoglu, Moritz Tenorth, Daniel Beßler
@license BSD
*/


:- module(knowrob_chemlab,
    [
        task_screwing_objects/3,
        visualize_chemlab_scene/1,
        visualize_chemlab_object/3,
        visualize_chemlab_highlight/1,
        visualize_chemlab_highlight/2,
        visualize_chemlab_highlights/1,
        inside_physical/3
    ]).
:- use_module(library('semweb/rdf_db')).
:- use_module(library('semweb/rdfs')).
:- use_module(library('owl')).
:- use_module(library('rdfs_computable')).
:- use_module(library('owl_parser')).
:- use_module(library('comp_temporal')).
:- use_module(library('knowrob_mongo')).

:- rdf_db:rdf_register_ns(knowrob, 'http://knowrob.org/kb/knowrob.owl#',  [keep(true)]).
:- rdf_db:rdf_register_ns(knowrob_chemlab, 'http://knowrob.org/kb/knowrob_chemlab.owl#', [keep(true)]).
:- rdf_db:rdf_register_ns(srdl2comp, 'http://knowrob.org/kb/srdl2-comp.owl#', [keep(true)]).
:- rdf_db:rdf_register_ns(knowrob_cram, 'http://knowrob.org/kb/knowrob_cram.owl#', [keep(true)]).

% define predicates as rdf_meta predicates
% (i.e. rdf namespaces are automatically expanded)
:-  rdf_meta
    task_screwing_objects(r,?,?),
    visualize_chemlab_scene(r),
    visualize_chemlab_object(+,+,r),
    visualize_chemlab_highlight(+),
    visualize_chemlab_highlight(+,+),
    visualize_chemlab_highlights(+).

is_screwable_on(CapName, ContName) :-
  owl_has(CapIndividual, knowrob:'name', literal(type(_,CapName))),
  owl_has(CapIndividual, knowrob_chemlab:'screwable', ContClass),
  owl_has(ContIndividual, knowrob:'name', literal(type(_,ContName))),
  owl_has(ContIndividual, rdf:'type', ContClass).

task_screwing_objects(Task, Cap, Container) :-
  task(Task),
  % There is a perceive subtask for container and cap
  findall(Type, (
    subtask(Task, Sub),
    rdfs_individual_of(Sub, knowrob:'UIMAPerception'),
    rdf_has(Sub, knowrob:'perceptionRequest', Desig),
    mng_designator(Desig, DesigJava),
    mng_designator_props(Desig, DesigJava, ['TYPE'], Type)
  ), Types),
  length(Types, 2),
  nth0(0, Types, Obj0),
  nth0(1, Types, Obj1),
  % Find container and cap
  (   is_screwable_on(Obj0, Obj1)
  ->  ( Cap = Obj0, Container = Obj1 )
  ;   ( Cap = Obj1, Container = Obj0 )
  ).
  
  

% % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % %
%
% Visualization methods
%

visualize_chemlab_highlights([ObjFrame|Rest]) :-
  visualize_chemlab_highlight(ObjFrame),
  visualize_chemlab_highlights(Rest).
  
visualize_chemlab_highlights([]) :-
  true.

visualize_chemlab_highlight(ObjFrame) :-
  atom_concat('/', ObjFrame, Buf),
  atom_concat(Buf, '_frame', MarkerId),
  highlight_object_mesh(MarkerId).

visualize_chemlab_highlight(ObjFrame, Color) :-
  atom_concat('/', ObjFrame, Buf),
  atom_concat(Buf, '_frame', MarkerId),
  highlight_object_mesh(MarkerId, Color).

visualize_chemlab_scene(T) :-
  % Query experiment information
  experiment(Exp, T),
  experiment_map(Exp, Map, T),
  % Query all occuring objects
  findall(Obj, (
    owl_has(Exp, knowrob:'occuringObject', ObjUrl),
    rdf_split_url(_, Obj, ObjUrl)
  ), Objs),
  clear_trajectories,
  % Show the PR2
  add_agent_visualization('PR2', pr2:'PR2Robot1', T, '', ''),
  % Show objects
  forall(
    member(Obj, Objs), ((
      designator_template(Map, Obj, Template),
      owl_has(Template, knowrob:'pathToCadModel', literal(type(_,MeshPath))),
      owl_has(Template, knowrob:'urdfName', literal(type(_,ObjFrame))),
      visualize_chemlab_object(ObjFrame, MeshPath, T)
    ) ; true)
  ).

visualize_chemlab_object(ObjFrame, MeshPath, T) :-
  remove_mesh_highlight(ObjFrame),
  
  mng_lookup_transform('/map', ObjFrame, T, Transform),
  % Extract quaternion and translation vector
  matrix_rotation(Transform, Quaternion),
  matrix_translation(Transform, Translation),
  % Publish mesh marker message
  add_mesh(ObjFrame, MeshPath, Translation, Quaternion).

inside_physical(Frame, Out, T) :-
  mng_lookup_position('/map', Frame, T, [X_Frame, Y_Frame, Z_Frame]),
  rdf_has(Out, srdl2comp:'box_size', literal(type(_,BoxSize))),
  rdf_has(Out, srdl2comp:'aabb_offset', literal(type(_,Offsets))),
  owl_has(Out, knowrob:'urdfName', literal(type(_,ObjFrame))),
  mng_lookup_transform('/map', ObjFrame, T, Transform),
  matrix_translation(Transform, [X_Out, Y_Out, Z_Out]),
  parse_vector(BoxSize, [X_Box,Y_Box,Z_Box]),
  parse_vector(Offsets, [X_Off,Y_Off,Z_Off]),
  X_Positive is X_Out + X_Off + X_Box,
  X_Negative is X_Out + X_Off - X_Box,
  Y_Positive is Y_Out + Y_Off + Y_Box,
  Y_Negative is Y_Out + Y_Off - Y_Box,
  Z_Positive is Z_Out + Z_Off + Z_Box,
  Z_Negative is Z_Out + Z_Off - Z_Box,
  (X_Negative > X_Frame, X_Positive < X_Frame;
  X_Negative < X_Frame, X_Positive > X_Frame),
  (Y_Negative > Y_Frame, Y_Positive < Y_Frame;
  Y_Negative < Y_Frame, Y_Positive > Y_Frame),
  (Z_Negative > Z_Frame, Z_Positive < Z_Frame;
  Z_Negative < Z_Frame, Z_Positive > Z_Frame).    
