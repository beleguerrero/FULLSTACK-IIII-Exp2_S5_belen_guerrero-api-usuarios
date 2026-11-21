package cl.duoc.mi_foro_usuarios.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data 
@NoArgsConstructor 
@AllArgsConstructor 
@Builder 
public class UsuarioRequestDTO {

    @NotBlank(message = "Falta usuario")
    private String usuario;

    @NotBlank(message = "Falta contraseña")
    private String password;

    @NotBlank(message = "Falta nombre")
    private String nombre;

    private String correo;

    @NotNull(message = "Falta tipo usuario")
    private Long tipoUsuarioId;

}
