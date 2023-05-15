import Component from "@glimmer/component";

export default class BotSelector extends Component {
  get botOptions() {
    return [
      { id: 1, name: "Default" },
      { id: 2, name: "Artist" },
      { id: 3, name: "Researcher" },
    ];
  }

  get value() {
    return this._value || 1;
  }

  set value(val) {
    this._value = val;
    const composer = this.args.outletArgs.model;
    composer.metaData = { gpt_persona: val };
  }
}
