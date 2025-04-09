/*Modulos com modificacoes:
  Riscvsingle()
  maindec()
  datapath()
  extend()*/
//Circuito combinacional: Ordem de declaração e "chamada" nao importa: Tudo executado simultanemanente.
module top(input  logic        clk, reset, 
           output logic [31:0] WriteData, DataAdr, 
           output logic        MemWrite);
 /*top() funciona como main() de C, faz controle de:
  imem(): Instruction Memory.
  dmem(): Data Memory.
  riscvsingle(): "Caminho" completo da inforação: controller() e datapath().*/
  /*entradas: 
    clock, reset: importante para controle das informações do controle para datapath.
  saidas:
    WriteData (informaçao a ser escrita em Write Register e MemWrite), 
    DataAdress (Endereço)
    MemWrite (no data memory para comandos como sw)*/
  /*Fios locais (representam "variáveis globais"):
  PC: Endereço com instrucao atualmente executada.
  Instr: INstrução extraída de PC.
  Read Data: Informação obtida ao executar Instr.*/
  logic [31:0] PC, Instr, ReadData;
  //declarando modulos utilizados nesse circuito:
  riscvsingle rvsingle(clk, reset, PC, Instr, MemWrite, DataAdr, 
                       WriteData, ReadData);
  imem imem(PC, Instr);
  dmem dmem(clk, MemWrite, DataAdr, WriteData, ReadData);
endmodule

module riscvsingle(input  logic        clk, reset, //*
                   output logic [31:0] PC,
                   input  logic [31:0] Instr,
                   output logic        MemWrite,
                   output logic [31:0] ALUResult, WriteData,
                   input  logic [31:0] ReadData);
  /*riscvsingle() representa o processador projetado para RISC-V, que contém controle e datapath.*/
  /*Entradas:
    clk e reset: Para controller (define ritmo de execução e restart, respectivamente).
    Instr: Instrução em riscv a ser executada.
    ReadData: O dado lido de ALUResult.
  Saídas:
    PC: Endereço da instrução atual.
    MemWrite: Sai de controller para definir em Data Memory (dmem) se escrita na memória.
      Memória obtida pela ULA, em ALUResult.
    ALUResult: Resultado da ULA (valor ou endereço).
    WritedData: Recebe Read Register 2 para ser ecrito com MemWrite.*/
  logic       ALUSrc, RegWrite, Jump, Zero, PCSrc;  //PCSrc declarado
  logic [1:0] ResultSrc, ImmSrc;
  logic [2:0] ALUControl;
  //variaveis locais: saidas do controle e entradas do datapath.
  controller c(Instr[6:0], Instr[14:12], Instr[30], Zero,
               ResultSrc, MemWrite, PCSrc,
               ALUSrc, RegWrite, Jump,
               ImmSrc, ALUControl);
  datapath dp(clk, reset, ResultSrc, PCSrc,
              ALUSrc, RegWrite, Jump, //Jump declarado como entrada
              ImmSrc, ALUControl,
              Zero, PC, Instr,
              ALUResult, WriteData, ReadData);
  //entardas e saidas melhor explicadas na declaração de cada modulo
endmodule

module controller(input  logic [6:0] op,
                  input  logic [2:0] funct3,
                  input  logic       funct7b5,
                  input  logic       Zero,
                  output logic [1:0] ResultSrc,
                  output logic       MemWrite,
                  output logic       PCSrc, ALUSrc,
                  output logic       RegWrite, Jump,
                  output logic [1:0] ImmSrc,
                  output logic [2:0] ALUControl);
  /*No controller tem:
    Entrada:
      Instr[6:0](op): Opcode, ultimos 6 bits de Instr.
      Instr[14:12](funct3): Function3 (complemento de 3 bits do opcode). Usado em quase todas as instruções.
      Instr[30](funct7b5):É o bit 5 do function7 (complemento de 7 bits do opcode). 
      Zero: Vem da ALU e determina se branch de beq deve ser atendido. Zero=1 entao branch é atendido.
    Saida:
      ResultSrc: Controla Result MUX (pos Data Memory), decide o Result para voltar à Register File.
        3 opcoes: ALUResult(resultado ALU), Data Read(leitura ALUResult) e PCAdd4(PC=PC+4).
      MemWrite: determina em Data Memory se tem escrita na memoria.
      PCSrc: Em PCSrc MUX qual proximo endereço de instrucao: Desvio de fluxo ou PC+4.
      ALUSrc: Na ULA decide qual a segunda entrada (Read Data2 RD2 ou immediato ImmExit).
      RegWrite: Em Register File determina se escreve no registrador rd(a3) do Write Data WD3.
      Jump: Controle para ativar o jump.
      ImmSrc: Em Imme Generator, seleciona qual parte da instrução se pega o immediate.
      ALUControl: Controle de 3 bits que na ULA, determina qual operação será feita.*/
  logic [1:0] ALUOp; //ALUOp, formado pelos ultimos 2 bits do opcode.
  logic       Branch; //Estabelece a solicitação de branch.

  maindec md(op, ResultSrc, MemWrite, Branch,
             ALUSrc, RegWrite, Jump, ImmSrc, ALUOp);
  //maindec: recebe opcode e controla com sinais todos outros componentes, incluindo ULAControl.
  aludec  ad(op[5], funct3, funct7b5, ALUOp, ALUControl);
  //aludec: faz o controle da ula especificamente.
  /*Recebe:
    op[5]: O quinto bit do opcode, ajuda a identificar subtraçao.
    funct3: Complemento do opcode para diferenciar instrucoes (and e or, por exemplo).
    funct7b5: Quinto bit do function7.
      Diferencia a subtração da adição.
      É o unico bit diferente em ambos fucntion7, necessario apenas passar esse quinto bit.
    ALUOp: Vindos diretamente dos dois ultimos bits do opcode, identifical principal das operações operações.*/
  assign PCSrc = Branch & Zero; 
  /*O sinal do branch é definido pelo Branch AND Zero. 
    Branch=1 somente quando há requerimento pela instrução e a condição for verificada como certa na ULA. 
    Vai para datapath controlar PCNext.*/
  //PCSrc é apenas para branches, jump(jal) é tratado separado
endmodule

module maindec(input  logic [6:0] op, //*
               output logic [1:0] ResultSrc,
               output logic       MemWrite,
               output logic       Branch, ALUSrc,
               output logic       RegWrite, Jump,
               output logic [1:0] ImmSrc,
               output logic [1:0] ALUOp);

  logic [10:0] controls;

  assign {RegWrite, ImmSrc, ALUSrc, MemWrite,
          ResultSrc, Branch, ALUOp, Jump} = controls; //Jump adicionado na declaração do controle principal do datapath
           //bits acumulados. Em ordem: 1+2+1+1+2+1+2=10bist totais.
           //saidas "juntadas" num array para melhor desenvolvimento.
  always_comb
    case(op) //avalia os casos pelo que recebe do opcode completo: 
    //8 sinais com 11 bits no total, na ordem:
    // RegWrite_ImmSrc_ALUSrc_MemWrite_ResultSrc_Branch_ALUOp_Jump
      7'b0000011: controls = 11'b1_00_1_0_01_0_00_0; // lw
      /*RegWrite:1 -> Ocorre escrita no registrador rd (Write Register) em Register File.
        ImmSrc:00 -> Todo o immediate está nos 12 primeiros bits da instrução.
        ALUSrc:1 -> ULA recebe o Immediato (ImmExit) como b(SrcB).
        MemWrite:0 -> Não há escrita na memoria em Data Memory.
        ResultSrc:01 -> escolhe Read Data (do Data Memory) como resultado final (Result).
          Ideia do lw é ler um endereço para colocar dado em algum registrador.
          Read Data (do bloco Data Memory) faz leitura do endereço calcukado por ULA.
          Por isso deve voltar como Write Data (em Register File) para escrita em rd (a3).
        Branch:0 -> Nao é um beq (ou B-type): Obrigatorialmente PCNext=PC+4.
        ALUOp:00 -> É load word, logo requer soma para calcular endereços de memória.
        Jump:0 -> Não é jal (sem pulo imediato).*/
      7'b0100011: controls = 11'b0_01_1_1_00_0_00_0; // sw
      /*RegWrite:0 -> Execução encerrada em Data Memory (sem escrita em registradores).
        ImmSrc:01 -> Imediato nos bits Instr[31-25, 11-7] (instrução).
        ALUSrc:1 -> ULA recebe o Immediato (ImmExit) como entrada.
        MemWrite:1 -> Tem escrita na memoria (bloco Data Memory) com endereço calculado na ULA.
        ResultSrc:00 -> Define Result como ALUResult. 
          Em sw, execução é encerrada em Data Memory, portanto não importa seu valor.
          Se valor não importa, pode-se manter o da ULA.
        Branch:0 -> Nao é um beq (ou B-type): Obrigatorialmente PCNext=PC+4.
        ALUOp:00 -> É store word, necessita de soma focada em endereços de memória.
        Jump:0 -> Não é jal (sem pulo imediato).*/
      7'b0110011: controls = 11'b1_xx_0_0_00_0_10_0; // R-type
      /*RegWrite:1 -> Escrita na meória (de Result (resultado) no bloco Register File).
        ImmSrc:xx -> Não há immediato (sinal não relevante).
        ALUSrc:0 -> ULA recebe Read Data 2(RD1) como entrada.
        MemWrite:0 -> Sem escrita na memoria.
        ResultSrc:00 -> Result(resultado) como ALUResult.
        Branch:0 -> Seleciona PC=PC+4.
        ALUOp:10 -> Direciona ULA para operação lógica ou artimética.
          ALUControl recebera ALUop, funct3 e fuunct7b5 para especificar a operação.
          Maindec serve para indicar que ULA fará algo aritmético/lógico (sem objetivo de endereço ou comparação, por exemplo).
        Jump:0 -> Não é jal (sem pulo imediato).*/ 
      7'b1100011: controls = 11'b0_10_0_0_00_1_01_0; // beq
      /*RegWrite:0 -> Naõ tem escrita em registrador.
        ImmSrc:10 -> Imediate vem de instr[31]+instr[7]+Instr[30-25]+INstr[11-8] = INstr[31,7,30:25,11:8].
          Cada instrução que usa imm tem seu próprio meio de organizá-lo:
            R-type: Nao tem immediate. Como nao é relevante, o xx estabelecido pelo maindec() não é considerado como valor valido para se operar (vai excluir o resultado desse immediate errado).
            I-type: INstr[31:20](lw).
            S-type: INstr[31:25, 11:7](sw).
            B-type: Instr[31,7,30:25,11:7]. (beq).
            U-type: Instr[31:11].
        ALUSrc:0 -> ULA recebe Read Data2(RD2) como entrada.
        MemWrite:0 -> Não tem escrita em memória.
        ResultSrc:00 -> Beq não necessita desse resultado para execução, portanto não importa seu valor.
          Se valor não importa, pode-se manter o da ULA.
        Branch:1 -> Demonstra a possibilidade de pulo no fluxo, ainda precisa confirmar pela ULA. 
        ALUOp:01 -> ULA realizará subtração para comparar valores (condicional do beq).
        Jump:0 -> Salto no fluxo é condicional, não imediato.*/
      7'b0010011: controls = 11'b1_00_1_0_00_0_10_0; // I-type ALU (addi)
      /*RegWrite:1 -> Ocorre escrita no registrador rd (Write Register) em Register File.
        ImmSrc:00 -> Todo o immediate está nos 12 primeiros bits da instrução.
        ALUSrc:1 -> ULA recebe o Immediato (ImmExit) como entrada.
        MemWrite:0 -> Não tem escrita em memória.
        ResultSrc:00 -> Define Result como ALUResult.
        Branch:0 -> Seleciona PC=PC+4.
        ALUOp:10 -> Direciona ULA para operação lógica ou artimética.
        Jump:0 -> Não é jal (sem pulo imediato).*/
      7'b1101111: controls = 11'b1_11_0_0_10_0_00_1; // jal
      /*RegWrite:1 -> Ocorre escrita no registrador rd (Write Register) em Register File.
        ImmSrc:11 -> Imediate vem de Instr[31:11].
        ALUSrc:0 -> ULA recebe Read Data2(RD2) como entrada.
        MemWrite:0 -> Não tem escrita em memória.
        ResultSrc:10 -> Result recebe PC=PC+4.
          Jal necessita guardar endereço de volta (PC+4) no registrador rd(a3) (por isso RegWrite=1).
          Só é possível quando Write Data em Register File possui o endereço.
          Por isso MUX de ResultSrc seleciona PC+4 e permite essa escrita.
        Branch:0 -> Não há condição para pulo de fluxo.
        ALUOp:00 -> Necessita de soma focada em endereços de memória.
        Jump:1 -> Pulo imediato para endereço calculado em datapath.*/
      default:    controls = 11'bx_xx_x_x_xx_x_xx_x; // impelmentação padrao
      /*OPCode não se encaixa, vai para definição padrão.*/
    endcase
endmodule

module aludec(input  logic       opb5,
              input  logic [2:0] funct3,
              input  logic       funct7b5, 
              input  logic [1:0] ALUOp,
              output logic [2:0] ALUControl);
  /*Entradas:
    op5: BIt 5 do opcode, verifica se instrucao usa subtraçao (tanto tipo R quanto B).
    funct3: Complemento do opcode (aparece em todos os formats). Ajuda a diferenciar instrucoes como and e or (ambos operações logicas mas com objetivos diferentes).
    funct7b5: Quinto bit de function7: function7 diferencia operações logicas como add e sub.
      Entre add e sub o unico bit diferente em funct7 é funct7[5], por isso pode-se usar apenas ele.
    ALUOp: Dois ultimos bits do opcode focado no primeiro controle da ULA (primeiro criterio de identificacao da operação da ULA).
  Saida:
  ALUControl: Controle de 3 bits, configura ULA a depender da operação e objetivos dessa operação*/
  logic  RtypeSub;
  assign RtypeSub = funct7b5 & opb5;  // TRUE for R-type subtract instruction
 
  /*A subtracao é usada tanto pelo R quanto pelo B type.
  Subtracao R type só acontece quando opb5=1 (tanto no opcode de beq quanto de sub op5=1) e funct7b5 (apenas no quinto bit de funct7 do sub=1).
  Se a ultima condiçao nao acontecer, vai se realizar uma subtração de comparação para beq.
  Considerar sub=subtraçaõ Rtype e subtraction=subtracao B type.*/
  always_comb
    case(ALUOp)
      2'b00:                ALUControl = 3'b000; // addition
      2'b01:                ALUControl = 3'b001; // subtraction
      default: case(funct3) // R-type or I-type ALU
                 3'b000:  if (RtypeSub) 
                            ALUControl = 3'b001; // sub
                          else          
                            ALUControl = 3'b000; // add, addi
                 3'b010:    ALUControl = 3'b101; // slt, slti
                 3'b110:    ALUControl = 3'b011; // or, ori
                 3'b111:    ALUControl = 3'b010; // and, andi
                 default:   ALUControl = 3'bxxx; // ???
               endcase
    endcase
    //addiction: soma feita para calcular endereços de memoria (sw e lw). add: adicao aritmetica.
    //subtraction: subtracao feita para comparar 2 valores (beq). sub: subtracao aritmetica.
    /*Criterio de decisao da operação:
      ALuOp ou opcode[1:0]:
        00 conclui-se que é comando de memoria (sw e lw), é preciso fazer uma adição (para endereços de memroia) logo ALUControl=000.
        01 conclui-se que é uma condicional para branch(nessa ULA apenas beq) portanto é subtracao para comparar dois valores, ALUControl=001.
        1x conclui-se que são operacoes logicas e artimeticas (o objetivo da instruçao e obter um unico resultado). 
          Para saber qual operação logica ou aritmetica é, precisa se uma segunda condição.
      Como ALuOp  ja usada, usa-se funct3:
        Funct3=000, é operação aritmetica (nessa ULA as principais são adicao ou subtracao).
          Nesse caso usa-se RtypeSub: Quando =1 significa que é subtração "aritmetica" (vem de necessidade artimetica),ALUControl=001.
          Se não significa que é uma substraçaõ aritmética, entao ALUControl=000.
        Se funct3=010 se faz um shift left (multiplicação com expoente de base 2) logo ALUControl=101.
        Se funct3= 110 se faz or, logo ALUControl=011.
        SE funct3= 111 se faz and, logo ALUControl=010.
        Caso funct3 nao encaixe em nenhuma das possibilidades definidas, a saída é inconclusiva (pode ser 0 ou1).*/
    /*ALUOp é definido em maindec() para determinar qual instrucao esta sendo executada (o que influencia na operação escolhida).
    Porem essa informação só é utilizada no ALUdec para escolher a operacao (instrucoes diferentes que precisam da mesma conta terao o mesmo ALUControl).
    Portanto a escrita aqui de soma aritmetica ou nao, por exemplo, é apenas para fazer a conexao com maindec(), mas ambos serão somas para a ULA no final.*/
endmodule

module datapath(input  logic        clk, reset, //*
                input  logic [1:0]  ResultSrc, 
                input  logic        PCSrc, ALUSrc,
                input  logic        RegWrite, Jump, //adiçao de jump, calculo de endereço-alvo para jal
                input  logic [1:0]  ImmSrc,
                input  logic [2:0]  ALUControl,
                output logic        Zero,
                output logic [31:0] PC,
                input  logic [31:0] Instr,
                output logic [31:0] ALUResult, WriteData,
                input  logic [31:0] ReadData);
  /*NO datapath tem:
    Entrada: 
      clk, reset: Usados no Register File.
      ResultSrc: Em Result MUX decide se o dado que retorna à Rister File é ALUResult, Read Data ou PC+4.
      PCSrc: Define em PCNext MUX se PC vai receber o endereço pra proxima instrução linearmente (PC=PC+4) ou um salto (branch).
      ALUSrc: Decide a segunda entrada da ALU é do ImmGenerator (extend) ou do Read Register 2(RD2).
      RegWrite: sai do controller para determinar escrita no RegisterFile em rd(a3).
      ImmSrc: Sai de controller. Cada tipo de instrução tem seu immediate em ordens diferentes, serve para determinar de onde sai o imediato.
      ALUControl: Sai do controller, decide qual vai ser a opração da ULA. Baeado no opcode (tem 3 bits).
    Saida:
      Zero: S ULA para indicar se uma subtração =0 (se uma comparaçao beq é correta ou nao).
      PC: Usado no datapath para calcular os dois possiveis endereços PCNext: Pc+4 e PC+immediate.
      Instr: Direciona diferentes pedaços para suas funcoes (opcode, imediato, alojar os regsitradores em Register File, ect).
      ALUResult: Rwsultado obtido da ULA, controlada por ALUControl.
      WriteData: Vem de rs2 (Read Data2) para Data Memory, que pode ser escrito em uma memoria.
      ReadData: Leitura de ALUResult: 
        Caso seja endereço, a informação é colocada em ReadData.
        Caso nao, nao é obtida nenhuma informaçaõ (valida).*/
  logic [31:0] PCNext, PCPlus4, PCTarget;
  logic [31:0] ImmExt;
  logic [31:0] SrcA, SrcB;
  logic [31:0] Result;
  logic        PCSrcFinal; //controle final para calculo de salto (ja que envolve beq e jal)
  /*Variaveis locais criadas:
    PCNext: Proximo endereço memoria RAM para ler proxima instrucao. 
    PCPlus4: Proximo endereço caso siga o fluxo normal de execucao. Uma das entradas do MUX.
    PCTarget: Proximo endereço caso haja um salto no fluxo . Segunda entrada do MUX.
    ImmExit: Immediato obtido a partir do bloco extend() e do sinal de controle ImmSrc.
    SrcA: Entrada 1 da ULA (a que vai de Read Data1 diretamente para a ULA).
    SrcB: Entrada 2 da ULA (a que pode ser um imediato ou Read Data2).
    Result: O Resultado apos Data Memory (que sai do MUX de ResultSrc e que volta para Register File).*/
  // next PC logic
  flopr #(32) pcreg(clk, reset, PCNext, PC); 
  adder       pcadd4(PC, 32'd4, PCPlus4);
  adder       pcaddbranch(PC, ImmExt, PCTarget);
   /*A sequencia de 4 chamadas acima foi para determianr o proximo endereço de leitura para PC (PCNetx):
  pcadd4 paz a conta PC=PC+4.
  pcaddbranch faz a conta PC=PC+immediate.
  pcmux faz a escolha de qual vai se tornar PCNext baseado em seu controle PCSrc.
  pcreg faz o registro de PCNext como o novo endereço a ser lido no proximo ciclo de clock.*/
  assign PCSrcFinal = PCSrc | Jump; //Controle que junta possibilidade de beq e jal
  /*Se PCSrc (controller) for 1 escolhe edenreço calculado para beq.
  Se Jump=1 escolhe endereço calculado  para jal.
  Com qualquer um =1, escolhe-se o endereço calculado por PCTarget.*/
  mux2 #(32)  pcmux(PCPlus4, PCTarget, PCSrcFinal, PCNext); //mux PCNext com sinal de controle atualizado
 
  // register file logic
  regfile     rf(clk, RegWrite, Instr[19:15], Instr[24:20], 
                 Instr[11:7], Result, SrcA, WriteData);
  extend      ext(Instr[31:7], ImmSrc, ImmExt);
   /*Na sequencia de 2 chamadas acima faz o "encaixe" das informações necessarias para comecar a processar a instrucao (registradores, imediatos, etc):
    rf: recebe os indices dos registradores envolvidos (rs1, rs2 e rd) e leem seus dados para colocar em read data1 2.
    ext: separa o immediato da instrucao geral e faz a extesao de bit (de 12bits para 32bits).*/
  // ALU logic
  mux2 #(32)  srcbmux(WriteData, ImmExt, ALUSrc, SrcB);
  alu         alu(SrcA, SrcB, ALUControl, ALUResult, Zero);
  mux3 #(32)  resultmux(ALUResult, ReadData, PCPlus4, ResultSrc, Result); //substitui 32'b0 por PCPlus4, aplica jal
  /*Jal necessita guardar endereço de volta (PC+4) no registrador rd(a3) (por isso RegWrite=1).
  Só é possível quando Write Data em Register File possui o endereço.*/
  /*A sequencia de 3 chamadas acima definem a execucao da ULA:
    srcbmux: faz a selecao de qual vai ser a segunda entrada da ULA.
    alu: Faz a operação em si determinada por ALUControl.
    resultmux: Decide qual vai ser a saída definitiva (de ALU+ Data memory).*/
endmodule

module regfile(input  logic        clk, 
               input  logic        we3, 
               input  logic [ 4:0] a1, a2, a3, 
               input  logic [31:0] wd3, 
               output logic [31:0] rd1, rd2);
   /*Entradas:
    clk: Controla os registradores (para todos atualizarem usando a mesma referencia).
    we3: Sinal do controller que indica se vai escrita em registrador ou nao.
    a1: Indice do rs1.
    a2: Indice do rs2;
    a3: Indice do rd.
    wd3: Write data que vai de Result (Data memory) para ser escrito em a3.
  Saidas:
    rd1: Dado lido de a1/rs1.
    rd2: Dado lido de a2/rs2.*/
  logic [31:0] rf[31:0];

  // three ported register file
  // read two ports combinationally (A1/RD1, A2/RD2)
  // write third port on rising edge of clock (A3/WD3/WE3)
  // register 0 hardwired to 0

  always_ff @(posedge clk) //sempre na subida do clock
    if (we3) rf[a3] <= wd3;	
    /*a principio rd=write registor=a3 fica apenas com seu indice. 
    Caso controller recebe um WriteRegisitor(we3)=1, é colcoado o dado de write data(wd3) nele.
    Se utiliza we3 e wd3 para identificar que sao do Register File, e nao do Data MEmory como we e wd.*/
  assign rd1 = (a1 != 0) ? rf[a1] : 0;
  assign rd2 = (a2 != 0) ? rf[a2] : 0;
  /*caso os indices em read register(a1) e read register2(a2) nao sejam zero (ja que o registrador x0 so vai armazenar 0), a informação deles é lida e colcoada em read data1(rd1) e read data2(rd2).*/
endmodule

module adder(input  [31:0] a, b,
             output [31:0] y);
  /*Entradas: a e b, que sao os operandos (os dois com 32 bits, já que é o padrao de tamanho dos registradores no risc-v 32bits).
  Saida: y que o resultado da soma (com 32 bits seguindo os operandos).*/
  assign y = a + b; //faz a soma.
endmodule

module extend(input  logic [31:7] instr, //*
              input  logic [1:0]  immsrc,
              output logic [31:0] immext);
  /*Entradas:
    Instr: Instrucao de onde vai sair o immediato (aqui no intervalo [31:7] pois os bits do immediate só podem estar espalhados nesse intervalo, já que [7:0] é apenas do opcode).
    Immsrc: Controller indicando quais serao os bits selecionados:
      R-type: Nao tem immediate. Como nao é relevante, o xx estabelecido pelo maindec() não é considerado como valor valido para se operar (vai excluir o resultado desse immediate errado).
      I-type: INstr[31:20](lw).
      S-type: INstr[31:25, 11:7](sw).
      B-type: Instr[31,7,30:25,11:7]. (beq).
      J-type: Instr[31,19:12,20, 30:21] (jal). 
  Saida:
    ImmNext: O imediato eselecionado e extendido*/
 /*R-type: Nao tem immediate. Como nao é relevante, o xx estabelecido pelo maindec() não é considerado como valor valido para se operar (vai excluir o resultado desse immediate errado).
  I-type: INstr[31:20](lw).
  S-type: INstr[31:25, 11:7](sw).
  B-type: Instr[31,7,30:25,11:7]. (beq).
  J-type: Instr[31,19:12,20, 30:21] (jal). */
  always_comb
    case(immsrc) 
      2'b00:   immext = {{20{instr[31]}}, instr[31:20]}; // I-type (lw, addi)
      //Adicionado tratamento do imediado para add1, segue I-format.
      2'b01:   immext = {{20{instr[31]}}, instr[31:25], instr[11:7]}; // S-type (sw)
      2'b10:   immext = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0}; // B-type (branches)
      /*ImmSrc corrigido para B-type (de 11 para 10).
      Na declaração em maindec() estava correto (10), porém na declaração em Extend() estava errado(11).*/
      2'b11:   immext = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0}; // J-type (jal)
      //Adicionado tratamento para imediato de Jal, segue J-type.
      default: immext = 32'bx; // undefined
    endcase             
endmodule

module flopr #(parameter WIDTH = 8) //por padrao utiliza variaveis de ate 8-1=7bits
              (input  logic             clk, reset,
               input  logic [WIDTH-1:0] d, 
               output logic [WIDTH-1:0] q);
  /*Entradas:
    clk, reset: para controlar o flip flop (clk faz o flip flop mudar de estado, enquanto reset faz o flil flp ser zerado).
    d: Informação (futuro estado final) a ser colocada no flip flop.
  Saida:
    q: Estado final do flip flop.*/
  always_ff @(posedge clk, posedge reset) //mudanças de estado só acontecem baseados no reset e no clock, independentemente.
    if (reset) q <= 0; // se reset=1, é necessario apagar a informação do flipflop, entao a saida é 0 (pois se armazena 0) -> sem endereço no PC.
    else       q <= d; //caso contrario é necessario armazenar a informação passada, dessa forma o estado atual (armazenado) vai ser o PCNext.
endmodule

module mux2 #(parameter WIDTH = 8)
             (input  logic [WIDTH-1:0] d0, d1, 
              input  logic             s, 
              output logic [WIDTH-1:0]y);
  /*Entrada:
    d0: Entrada do mux
    d1: Entrada do mux
    s: Controle do mux
  Saida
    y: Saida do MUX*/
    //MUX de 2 entradas, 1 saida e 1 controle.
    //Exep-mplo para melhor entendimento.
    //mux2 #(32)  pcmux(PCPlus4, PCTarget, PCSrc, PCNext);
  assign y = s ? d1 : d0; //se s=1 y=d1, se s=0 entao y=d0.
endmodule

module mux3 #(parameter WIDTH = 8)
             (input  logic [WIDTH-1:0] d0, d1, d2,
              input  logic [1:0]       s, 
              output logic [WIDTH-1:0] y);

  assign y = s[1] ? d2 : (s[0] ? d1 : d0);  //se s=1x entao y=d2, se s=01 entao y=d1 e se s=00 entao y=d0.
endmodule

module imem(input  logic [31:0] a, //imem é o nome do bloco instruction memory
            output logic [31:0] rd);
  /*Recebe a com 32 bits: Representa o PC (endereço com a instrucao atual)
  Devolve rd com 32 bits: INstrucao lida*/
  logic [31:0] RAM[63:0]; //matriz de 64 linhas, cada linha com 32 bits -> memoria do computador

  initial
      $readmemh("riscvtest.txt",RAM);
      /*RAM: memoria auxiliar temporaria e rapida da CPU para acessar informações utilizadas atualmente pela CPU.
      Na RAM vai ficar todas as instruções da mesma forma que o computador, ao ser requisitado para executar um procedimento, retira essas instrucoes da memoria secundária para colocar na RAM e ter mais acesso.*/
  assign rd = RAM[a[31:2]]; /*como a linha vem com instrução e resposta, rd recebe todas as linhas com os bits de 2 ate 31 que tem apenas as entradas (instrucoes).
  preenche a memoria do computador com as instrucçoes, cada uma correspondendo à 1 endereço (pois a instrucao tem 32 bits assim como cada parte da memoria).*/
endmodule

module dmem(input  logic        clk, we, //dmem é o nome do bloco data memory
            input  logic [31:0] a, wd,
            output logic [31:0] rd);
  /*Entradas:
  clk: Clock
  we: Mem (memory) write: Sinal para fazer a escrita da informação recediba por "a"  no registrador wd (Write Data), em comandos como sw.
  a: saída obtida pela ULA (pode ser um numero de contas aritmeticas/logicas ou um endereço no caso de lw, sw e jal.
  wd: Write Data: Dado recebido pelo Register File (regfile) em comandos como sw.
    Nesse caso a=endereço de memória e we=1, para escrever wd em a.
  rd: Read Data: Quando a=endereço de memória rd é o dado que esse endereço carrega..*/
  logic [31:0] RAM[63:0];

  // word aligned -> "puxa" a memoria do computador para se "passar a frente", assim o bloco Imem pode começar a execucao de outro comando.
  assign rd = RAM[a[31:2]]; // word aligned

  always_ff @(posedge clk) //ação que sempre vai acontecer na subida do clock
    if (we) RAM[a[31:2]] <= wd; //se Memory Write=1, a inforação recebida na entrada "a" (vindo da ula) é escrita 
endmodule

module alu(input  logic [31:0] a, b,
           input  logic [2:0]  alucontrol,
           output logic [31:0] result,
           output logic        zero);
  /*Entradas:
    a: Um valor a ser operado.
    b: Outro valor a ser operado.
    alucontrol: Contrle de 3 bits que define qual a operação entre a e b.
      Ja definido em ALUControl: definida a operação independente da finalidade.
  Saida:
    result: O resultado da operação f(a,b).
    zero: Comparação entre a e b: se a-b=0 (a=b) zero=1, se nao zero=0.*/
  logic [31:0] condinvb, sum;
  logic        v;              // overflow
  logic        isAddSub;       // true when is add or subtract operation
  /*Variaveis locais:
    condinvb: avalia se necessita inverter b para alguma operação como a-b =a +(-b).
    sum: resultado da soma (a princio valor versatil, pois pode ser tanto a=b quando a=(-b)).
    v; Verifica se tem overflow (quando o numero nao pode ser representado na quantidade de bits determinada).
    isAddSub: Verifica se a operaçao necessaria é soma ou subtraçao (para avaliar coisas como a possibilidade de overflow).*/
  assign condinvb = alucontrol[0] ? ~b : b; //~b apenas faz a inversao de bits, nao o complemento de 2 compelto.
   /*Se opcode[0]=1, configura beq, necessita de subtraçao, que é a+(-b).
  Logo a condição de inversao de b (condinvb) é baseado no alucontrol[0]: Se alucontrol[0]=1 a inversao é feita, se nao (alucontrl[0]=0) nao é feita inversao.
  Caso nao mantém +b para a soma a+b*/
  assign sum = a + condinvb + alucontrol[0];
  /*sum: a soma entre a e b (invertido pela necessidade ou nao) alucontrol[0]. Dessa forma estabelece a soma eficiente:
    Conssiderando que ha tanto numeros positivos quanto negativos, usa o complemento de 2 para representa-los em binario.
     Se alucontrol[0]=0, indica uma soma, logo nao tem conversao de b e, portanto, nao se aplica o complemento de 2.
     Se alucontrol[0]=1, indica subtração. Dessa forma precisa aplicar o "contrario" do complemento de 2.
      Como isso envolve somar 1, já pode incluir alucontrol[0] na jogada.
    Dessa forma se alucontrol[0]=0 ele nao atrapalha a soma e se alucontrol[0]=1 ele ajuda a fazer a subtraçaõ.*/
  assign isAddSub = ~alucontrol[2] & ~alucontrol[1] |
                    ~alucontrol[1] & alucontrol[0];
   /*Como adicao e subtração sao usadas para diferentes contextos (adicao: Aritmetica e endereço. subtracao: aritmetica e comparacao) e podem usar o mesmo circuito, 
  Colocar uma verificao apenas ambas otimiza as operações mais utilizadas.
  Concisderado que isAddSub=1 significa que é adicao/subtracao e isAddSub=0 significa que nao tem adicao/subtracao, alem de nao envolver muitas operações:
    ~alucontrol[2] & ~alucontrol[1] serve para verificar se ambos sao 0: No modelo 00x significa que pode ser tanto uma adição quanto subtraçao.
    ~alucontrol[1] & alucontrol[0] serve se alucontrol[1]=0 e alucontrol[0]=1. Se alucontrol[0]=1 entao a operação é especificamente subtração.
    Se um ou outro acontecer, significa que vai ter adicao ou subtracao.
    Se nao, a operação da ULA vai ser algo fora disso (and, or, shift, etc).*/
  always_comb
    case (alucontrol)
      3'b000:  result = sum;         // add
      3'b001:  result = sum;         // subtract
      3'b010:  result = a & b;       // and
      3'b011:  result = a | b;       // or
      3'b100:  result = a ^ b;       // xor
      3'b101:  result = sum[31] ^ v; // slt -> set less than: compara e determina qual valor é menor (aritmetico).
      3'b110:  result = a << b[4:0]; // sll
      3'b111:  result = a >> b[4:0]; // srl
      default: result = 32'bx;
    endcase
    /*casos baseados na alucontrol:
      000: operaçao é uma soma e ja foi calculada pelo sum, logo result=sum.
      001: operação de subtracao, também ja calculada pelo sum, entao result=sum.
      010: operação AND, logo result= a AND b.
      011: OR, logo result=a OR b.
      100: XOR, logo result= a XOR b.
      101: slt é para acharo minimo, logo result= sum[31]^v.
        sum[31] é o bit mais significativo da juncao de a com b. Levando como referencia a:
          Se sum[31]>0 entao a>b, pois a-b>0.
          Se sum[31]<0 entao a<b, pois a-b<0.
        
      110: shift left.
      111; shift right.*/
  assign zero = (result == 32'b0);
  assign v = ~(alucontrol[0] ^ a[31] ^ b[31]) & (a[31] ^ sum[31]) & isAddSub;
  /*O overflow acontece quando:
    Adicao: Numeros com sinais iguais (positivo e positivo, negativo e negativo).
    Subtraçao : Sinais diferentes (positivo e negativo).
  A logica para verificar se tem overflow é:
    ~(alucontrol[0] ^ a[31] ^ b[31]): Avalia se os sinais dos operandos para prever o sinal do resultado:
      Somar dois positivos deve dar um positivo e dois negativos deve dar um negativo.
      Se alucontrol[0]=0 é soma, se a[31]=b[31] entao vai ter overflow -> vai dar 1
      Se alucontrol[0]=1 entao e subtracao, se a[31]!=b[31] entao vai ter overflow. -> vai dar 1
      Para isso serve o XOR e NOt no final (a tabela verdade confirma).
    (a[31] ^ sum[31]): Sabendo do sinal final dependendo dos sinais dos operandos:
      Se for soma e o sinal de a(a[31])=sinal da soma(sum[31]), entao teve overflow. ->vai dar 1
      Se for soma e o sinal de a(a[31])=sinal da soma(sum[31]), entao teve overflow. -> vai dar 1
      Tabela verdade também confirma.
    isAddSub: Serve para limitar esse sinal de overflow apenas a adicao e subtração.
      Se nao for nenhuma das operações, isAddSub=0, zerando o resultado final.
    Colocando isso nos ANDs, v=1 somente quando todas essas verificacoes forem 1. Qualquer coisa fora disso desqualifica o overflow da soma ou subtracao.*/
endmodule